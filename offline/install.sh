#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
umask 077
. ./unix-common.sh
. ./offline-unix.sh
mode="${1:---help}"
if [[ "$mode" == --help ]]; then
  printf '%s\n' '用法：bash install.sh --prepare --admin-email owner@example.com' \
    '首次准备后将本节点授权保存为 activation.json，再运行 --activate。' \
    '原目录更新发行文件后运行 --upgrade；--reinstall 保留数据重建应用。' \
    '--status 查看当前服务状态。不会拉取镜像，不在用户机器编译业务源码。'
  exit 0
fi
shift
case "$mode" in --prepare|--activate|--upgrade|--reinstall|--status) ;; *) fail '未知操作。'; exit 1 ;; esac
lock_installer
verify_bundle
find_docker
check_unix_owner
import_offline_images
compose() { docker compose --env-file config/compose.env -f compose.yaml -f "compose.${ARCH}.json" "$@"; }
if [[ "$mode" == --status ]]; then
  [[ -f config/compose.env ]] || { fail '尚未准备安装。'; exit 1; }
  compose ps
  exit 0
fi
private_directory config
if [[ "$mode" == --prepare || "$mode" == --activate ]]; then
  identity="$(host_identity)"
  setup_command=(docker run --rm --pull never --user 0:0 -v "${PWD}/config:/config")
  setup_arguments=(--machine-id "$identity" --runtime-image "$runtime_image" --web-image "$web_image")
  if [[ "$mode" == --activate ]]; then
    [[ -f activation.json && ! -L activation.json ]] || { fail '请先保存本节点的 activation.json。'; exit 1; }
    chmod 600 activation.json
    setup_command+=(-v "${PWD}/activation.json:/activation.json:ro")
    setup_arguments+=(--activation /activation.json)
  fi
  "${setup_command[@]}" "$runtime_image" python -m packages.deployment_license.install_config \
    "${setup_arguments[@]}" "$@"
fi
[[ -f config/installation.json && -f config/compose.env && -f config/node.env ]] || { fail '缺少原节点完整配置，请先恢复。'; exit 1; }
if [[ "$mode" == --upgrade || "$mode" == --reinstall ]]; then
  # Do not silently downgrade an existing compatible installation.
  old_runtime="$(read_setting config/compose.env TRANSDOC_RUNTIME_IMAGE)"
  old_version="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$old_runtime")"
  new_version="$(read_setting release.env APPLICATION_VERSION)"
  docker run --rm --pull never --network none "$runtime_image" python -c \
    'import re,sys; a,b=sys.argv[1:]; valid=lambda v:bool(re.fullmatch(r"\d+\.\d+\.\d+",v)); assert valid(a) and valid(b) and tuple(map(int,a.split(".")))<=tuple(map(int,b.split("."))), "拒绝降级或未知旧版本"' "$old_version" "$new_version"
  docker run --rm --pull never --user 0:0 -v "${PWD}/config:/config" "$runtime_image" python -m packages.deployment_license.install_origins
fi
compose config --quiet
if [[ "$mode" == --prepare ]]; then
  compose up -d --no-deps --wait --wait-timeout 180 postgres redis
  printf '%s\n' '数据库和 Redis 已准备。尚未启动业务处理。' \
    '请将上方节点编号提交授权中心，将本节点凭证保存为 activation.json，再运行 --activate。'
  exit 0
fi
[[ -f config/activation.token && -f config/authority-public.pem ]] || { fail '请先完成本节点授权。'; exit 1; }
compose stop --timeout 30 dispatcher
compose stop --timeout -1 worker
compose up -d --wait --wait-timeout 180 postgres redis
private_directory backups
compose run --rm --no-deps -e "BACKUP_FILE=pre-upgrade-$(date -u +%Y%m%dT%H%M%SZ).dump" backup
compose run --rm --no-deps storage-init
compose run --rm --no-deps migrate
if [[ -f config/bootstrap.json ]]; then
  compose run --rm --no-deps -v "${PWD}/config/bootstrap.json:/run/bootstrap.json:ro" api \
    python -m services.api.src.modules.deployment_licenses.bootstrap --file /run/bootstrap.json
fi
compose up -d --no-deps --force-recreate license-agent
compose up -d --no-deps --force-recreate --wait --wait-timeout 180 api web
compose exec -T api python -m packages.deployment_license.wait_ready
compose exec -T web wget -q -O /dev/null http://127.0.0.1:8080/api/v1/health/ready
compose up -d --no-deps --force-recreate worker dispatcher
docker run --rm --pull never --user 0:0 -v "${PWD}/config:/config" "$runtime_image" \
  python -m packages.deployment_license.pin_release --runtime-image "$runtime_image" --web-image "$web_image"
if ! compose exec -T license-agent python -m services.api.src.modules.deployment_licenses.node_agent --once; then
  printf '%s\n' '应用已就绪，节点资料/版本同步暂未完成，稍后重试。'
fi
port="$(read_setting config/compose.env TRANSDOC_HTTP_PORT)"
printf '部署完成。本机默认入口 http://localhost:%s ，实际公开地址以原配置为准。\n' "$port"
printf '%s\n' '初始账号密码仅在本机 config/bootstrap.json；请私密查看并在登录后修改。原账号不会被重置。'
