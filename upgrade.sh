#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
P=/www/server/panel
[[ -d "$P" ]] || { echo "Panel not found"; exit 1; }
B="/www/server/panel.upgrade-backup.$(date +%Y%m%d%H%M%S)"
systemctl stop bt-task bt 2>/dev/null || true
cp -a "$P" "$B"
echo "已完整备份到：$B"
echo "当前升级脚本只执行备份和停服，不自动覆盖源码；正式升级需先完成版本迁移测试。"
