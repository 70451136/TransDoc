#!/usr/bin/env bash
# Only checksum-verified local images are loaded. No registry fallback.
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

verify_bundle() {
  [[ -f checksums.sha256 && ! -L checksums.sha256 ]] || { fail '缺少校验清单。'; return 1; }
  local digest name extra seen='' count=0
  while read -r digest name extra; do
    [[ "$digest" =~ ^[a-f0-9]{64}$ && -z "$extra" ]] || { fail '校验清单格式无效。'; return 1; }
    case "$name" in
      install.sh|unix-common.sh|offline-unix.sh|Start.command|start.sh|compose.yaml|release.env|README.md|PDF.md|SOURCE-NOTICE.md|images-amd64.tar.gz|images-arm64.tar.gz|images.amd64.env|images.arm64.env|compose.amd64.json|compose.arm64.json) ;;
      *) fail '校验清单包含非发行文件。'; return 1 ;;
    esac
    [[ " $seen " != *" $name "* ]] || { fail '校验清单包含重复文件。'; return 1; }
    seen="$seen $name"; count=$((count + 1))
    [[ -f "$name" && ! -L "$name" ]] || { fail "发行文件缺失或为链接：$name"; return 1; }
    printf '校验 %s …\n' "$name"
    [[ "$(hash_file "$name")" == "$digest" ]] || { fail "文件校验失败：$name。请重新获取完整发行包。"; return 1; }
  done < checksums.sha256
  [[ "$count" == 16 ]] || { fail '发行文件数量不完整。'; return 1; }
  [[ "$(read_setting release.env INSTALLER_REVISION)" == 13 ]] || return 1
  [[ "$(read_setting release.env IMAGE_CONTRACT)" == 7 ]] || return 1
  local target
  target="$(read_setting release.env TARGET_OS)"
  case "$(uname -s):$target" in Linux:linux|Darwin:macos) ;; *) fail '请使用适合当前操作系统的安装包。'; return 1 ;; esac
}

import_offline_images() {
  local role image actual metadata
  ARCH="$(normalize_arch "$(docker info --format '{{.Architecture}}')")"
  metadata="images.${ARCH}.env"
  REVISION="$(read_setting release.env APPLICATION_REVISION)"
  [[ "$REVISION" =~ ^[a-f0-9]{40}$ ]] || return 1
  [[ "$(docker info --format '{{json .DriverStatus}}')" == *io.containerd.snapshotter* ]] || {
    fail '本包需要启用 containerd 镜像存储，详见安装说明。'; return 1;
  }
  runtime_image="$(read_setting "$metadata" RUNTIME_IMAGE)"
  web_image="$(read_setting "$metadata" WEB_IMAGE)"
  local missing=0
  for role in RUNTIME WEB POSTGRES REDIS; do
    image="$(read_setting "$metadata" "${role}_IMAGE")"
    [[ "$image" =~ ^sha256:[a-f0-9]{64}$ ]] || { fail '镜像未固定到内容摘要。'; return 1; }
    if ! docker image inspect "$image" >/dev/null 2>&1; then missing=1; fi
  done
  if [[ "$missing" == 1 ]]; then
    printf '导入本机 %s 离线镜像，不访问镜像仓库 …\n' "$ARCH"
    docker load --input "images-${ARCH}.tar.gz"
  fi
  for role in RUNTIME WEB POSTGRES REDIS; do
    image="$(read_setting "$metadata" "${role}_IMAGE")"
    actual="$(docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' "$image")"
    [[ "$actual" == "$image linux/$ARCH" ]] || { fail "镜像架构或摘要不一致：$role"; return 1; }
  done
  # Docker templates verify labels without requiring jq/Python on the host.
  for image in "$runtime_image" "$web_image"; do
    actual="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}} {{index .Config.Labels "com.transdoc.installer-contract"}} {{index .Config.Labels "org.opencontainers.image.version"}}' "$image")"
    [[ "$actual" == "$REVISION 7 $(read_setting release.env APPLICATION_VERSION)" ]] || { fail '前后端镜像版本不一致。'; return 1; }
  done
  export TRANSDOC_RUNTIME_IMAGE="$runtime_image" TRANSDOC_WEB_IMAGE="$web_image"
  export DOCKER_DEFAULT_PLATFORM="linux/$ARCH"
}
