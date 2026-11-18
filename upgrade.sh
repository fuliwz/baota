#!/usr/bin/env bash
set -Eeuo pipefail

# 用于已安装的宝塔面板切换到 7.4.0；归档本身是 update.sh 升级包。
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
[[ -f /www/server/panel/BT-Panel ]] || { echo "未找到已安装的宝塔面板。" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "需要 systemd。" >&2; exit 1; }
TMP="$(mktemp -d -t bt740-update.XXXXXX)"
BACKUP="/www/server/panel.before-7.4.0.$(date +%Y%m%d%H%M%S)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

echo "升级/降级前完整备份面板目录：$BACKUP"
cp -a /www/server/panel "$BACKUP"

URL="${PANEL_ARCHIVE_URL:-https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip}"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 --proto "=https" --tlsv1.2 -o "$TMP/panel.zip" "$URL"
[[ -s "$TMP/panel.zip" ]] || { echo "升级包为空。" >&2; exit 1; }
if [[ -n "${EXPECTED_SHA256:-}" ]]; then
  [[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "SHA256 格式错误。" >&2; exit 1; }
  echo "$EXPECTED_SHA256  $TMP/panel.zip" | sha256sum --check --status || { echo "SHA256 校验失败。" >&2; exit 1; }
else
  echo "警告：未设置 EXPECTED_SHA256。" >&2
fi

python3 - "$TMP/panel.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    bad=[]
    for item in z.infolist():
        name=item.filename.replace("\\","/")
        if name.startswith("/") or ".." in name.split("/"): bad.append(name)
        if ((item.external_attr >> 16) & 0o170000) == 0o120000: bad.append(name)
    if bad: raise SystemExit("危险 ZIP 成员: " + repr(bad[:10]))
    if not any(n.endswith("panel/update.sh") for n in z.namelist()):
        raise SystemExit("缺少 panel/update.sh，不是预期的离线升级包。")
PY
mkdir -p "$TMP/extract"
unzip -q "$TMP/panel.zip" -d "$TMP/extract"
UPDATE_SCRIPT="$(find "$TMP/extract" -type f -path "*/panel/update.sh" -print -quit)"
[[ -n "$UPDATE_SCRIPT" ]] || { echo "未找到 update.sh。" >&2; exit 1; }

systemctl stop bt-task.service bt.service 2>/dev/null || true
(
  cd "$(dirname "$UPDATE_SCRIPT")"
  bash ./update.sh
)

if [[ ! -f /www/server/panel/BT-Panel ]]; then
  echo "更新后面板入口缺失，尝试恢复备份。" >&2
  rm -rf /www/server/panel
  cp -a "$BACKUP" /www/server/panel
  systemctl start bt.service 2>/dev/null || true
  systemctl start bt-task.service 2>/dev/null || true
  exit 1
fi
systemctl daemon-reload
systemctl restart bt.service
sleep 5
if ! systemctl is-active --quiet bt.service; then
  journalctl -u bt.service -n 100 --no-pager >&2 || true
  echo "服务启动失败。为避免覆盖升级脚本对数据库/配置的迁移，备份保留于：$BACKUP" >&2
  echo "请检查日志后手动决定是否恢复整个目录。" >&2
  exit 1
fi
systemctl restart bt-task.service 2>/dev/null || true
echo "已执行 7.4.0 离线升级包。备份目录：$BACKUP"
echo "检查面板版本和登录功能，并确保云安全组放行面板端口。"
