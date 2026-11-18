#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
PANEL=/www/server/panel
echo "此脚本只卸载宝塔面板服务和面板程序目录，不会自动卸载 Nginx/MySQL/PHP 或删除网站、数据库。" 
read -r -p "输入 KEEP 保留面板目录，输入 REMOVE 将面板目录移入时间戳备份：" answer
[[ "$answer" == KEEP || "$answer" == REMOVE ]] || { echo "已取消。"; exit 1; }
systemctl disable --now bt-task.service bt.service 2>/dev/null || true
rm -f /etc/systemd/system/bt.service /etc/systemd/system/bt-task.service
systemctl daemon-reload
if [[ "$answer" == REMOVE && -d "$PANEL" ]]; then
  DEST="/www/server/panel.uninstalled.$(date +%Y%m%d%H%M%S)"
  mv "$PANEL" "$DEST"
  echo "面板目录已移动至：$DEST"
fi
echo "卸载操作完成。系统依赖包和 Web 服务组件均予以保留。" 
