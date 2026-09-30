#!/usr/bin/env bash
# Explicit opt-in only. Never removes existing Docker/containerd installations.
set -euo pipefail
if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then exit 0; fi
[[ "${EUID}" == 0 ]] || { echo 'Run as root to install the engine.' >&2; exit 1; }
[[ -f /etc/os-release ]] || exit 1
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:12|debian:13) ;;
  *) echo 'Automatic engine setup supports Ubuntu 22.04/24.04/26.04 and Debian 12/13 only.' >&2; exit 1 ;;
esac
if command -v docker >/dev/null || command -v containerd >/dev/null; then
  echo 'An engine is already present but not ready. Resolve it manually; it will not be replaced.' >&2
  exit 1
fi
apt-get update
apt-get install -y ca-certificates curl
install -d -m 0755 /etc/apt/keyrings
curl --fail --show-error --silent --proto '=https' --tlsv1.2 \
  "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/transdoc-docker.asc
chmod 0644 /etc/apt/keyrings/transdoc-docker.asc
printf '%s\n' "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/transdoc-docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/transdoc-docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker info >/dev/null
docker compose version
