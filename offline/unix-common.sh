#!/usr/bin/env bash
# Portable Bash 3.2 helpers. Loading this file has no side effects.
fail() { printf '%s\n' "$*" >&2; return 1; }

read_setting() {
  local file="$1" key="$2" value
  [[ -f "$file" && ! -L "$file" ]] || { fail "缺少或不安全的文件：$file"; return 1; }
  [[ "$(grep -c "^${key}=" "$file")" == 1 ]] || { fail "配置键缺失或重复：$key"; return 1; }
  value="$(sed -n "s/^${key}=//p" "$file")"
  [[ -n "$value" && "$value" != *$'\r'* ]] || return 1
  printf '%s' "$value"
}

find_docker() {
  # Docker Desktop may install the CLI for this user only.
  if ! command -v docker >/dev/null 2>&1; then
    PATH="${HOME}/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:${PATH}"
    export PATH
  fi
  command -v docker >/dev/null 2>&1 || { fail '请先安装并启动 Docker，参阅本包 README.md。'; return 1; }
  local endpoint context
  context="$(docker context show)"
  endpoint="${DOCKER_HOST:-$(docker context inspect "$context" --format '{{.Endpoints.docker.Host}}')}"
  [[ "$endpoint" == unix://* ]] || { fail '本机离线安装仅支持本机 Unix Docker socket；不能向远程 Docker 发送配置。'; return 1; }
  [[ "$(docker info --format '{{.OSType}}')" == linux ]] || { fail '需要可用的 Linux 容器引擎。'; return 1; }
  docker compose version >/dev/null
}

lock_installer() {
  [[ ! -L .installer.lock.d ]] || { fail '安装锁路径不安全。'; return 1; }
  mkdir .installer.lock.d 2>/dev/null || {
    fail '安装器已运行或上次中断留下安装锁。先确认没有安装进程，再清理本目录 .installer.lock.d。'; return 1;
  }
  printf '%s\n' "$$" > .installer.lock.d/pid
  trap 'rm -f .installer.lock.d/pid; rmdir .installer.lock.d 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

host_identity() {
  local value
  case "$(uname -s)" in
    Darwin) value="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F '\"' '/IOPlatformUUID/ {print $(NF-1)}')" ;;
    Linux) [[ -r /etc/machine-id ]] || { fail '缺少稳定的 /etc/machine-id，未创建节点。'; return 1; }
           value="$(cat /etc/machine-id)" ;;
    *) fail '此安装器只支持 macOS 或 Linux。'; return 1 ;;
  esac
  [[ "$value" =~ ^[A-Fa-f0-9-]{32,36}$ ]] || { fail '机器标识无效，未生成随机替代身份。'; return 1; }
  printf '%s' "$value"
}

private_directory() {
  local name="$1"
  [[ ! -L "$name" ]] || { fail "私密目录不能是符号链接：$name"; return 1; }
  mkdir -p "$name"
  chmod 700 "$name"
}

check_unix_owner() {
  local project="${COMPOSE_PROJECT_NAME:-transdoc-licensed}" ids id owner path name volumes
  [[ "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
  path="$(pwd -P)"
  ids="$(docker ps -aq --filter "label=com.docker.compose.project=$project")" || return 1
  if [[ -n "$ids" ]]; then
    for id in $ids; do
      owner="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$id")" || return 1
      [[ "$owner" == /* && -d "$owner" ]] || { fail '无法确认原安装目录，请恢复原目录后继续。'; return 1; }
      [[ "$(cd "$owner" && pwd -P)" == "$path" ]] || { fail '此 Docker 项目属于另一安装目录，请回原目录升级。'; return 1; }
    done
    for name in installation.json compose.env node.env; do
      [[ -f "config/$name" && ! -L "config/$name" ]] || { fail '请恢复完整原配置；不能重置现有数据库密码。'; return 1; }
    done
  else
    volumes="$(docker volume ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}')" || return 1
    if [[ -z "$volumes" ]]; then
      volumes="$(docker volume ls --format '{{.Name}}')" || return 1
      volumes="$(printf '%s\n' "$volumes" | grep -E "^${project}_(database|cache|storage)$" || true)"
    fi
    [[ -z "$volumes" ]] || { fail '发现原数据卷但没有安装归属证据，请先恢复原安装。未生成新身份。'; return 1; }
  fi
  for name in installation.json compose.env node.env bootstrap.json authority-public.pem activation.token; do
    [[ ! -L "config/$name" ]] || { fail '私密配置不能是符号链接。'; return 1; }
  done
}

normalize_arch() {
  case "$1" in
    x86_64|amd64) printf amd64 ;;
    aarch64|arm64) printf arm64 ;;
    *) fail '只支持 x86_64 和 ARM64。'; return 1 ;;
  esac
}
