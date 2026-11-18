#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
read -r -p "输入 KEEP 保留面板数据，输入 REMOVE 将面板目录移入备份：" answer
[[ "$answer" == KEEP || "$answer" == REMOVE ]] || { echo "已取消"; exit 1; }
systemctl disable --now bt-task bt 2>/dev/null || true
rm -f /etc/systemd/system/bt.service /etc/systemd/system/bt-task.service
systemctl daemon-reload
if [[ "$answer" == REMOVE && -d /www/server/panel ]]; then
  mv /www/server/panel "/www/server/panel.uninstalled.$(date +%Y%m%d%H%M%S)"
fi
echo "服务已移除；系统依赖包保留，避免影响其他应用。"
