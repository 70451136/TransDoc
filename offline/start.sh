#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
printf '%s\n' 'TransDoc 离线部署' '1 准备安装  2 导入授权并启动  3 保留数据升级  4 查看状态  0 退出'
read -r -p '请选择：' choice
case "$choice" in
  1)
    if [[ -f config/installation.json ]]; then bash ./install.sh --prepare
    else read -r -p '管理员邮箱：' email; bash ./install.sh --prepare --admin-email "$email"; fi ;;
  2) bash ./install.sh --activate ;;
  3) bash ./install.sh --upgrade ;;
  4) bash ./install.sh --status ;;
  0) exit 0 ;;
  *) printf '%s\n' '无效选项。' >&2; exit 1 ;;
esac
read -r -p '按回车关闭 …' _
