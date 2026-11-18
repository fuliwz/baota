#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Apply an offline release update archive such as LinuxPanel-7.4.0.zip.
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
PANEL=/www/server/panel
[[ -f "$PANEL/BT-Panel" ]] || { echo "未找到完整的已安装面板，请先运行 install.sh。" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "此脚本需要 systemd。" >&2; exit 1; }

URL="${PANEL_ARCHIVE_URL:-https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip}"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
TMP="$(mktemp -d -t bt-version-update.XXXXXX)"
BACKUP="/www/server/panel.before-version-change.$(date +%Y%m%d%H%M%S)"

cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

echo "[宝塔版本切换] 完整备份面板目录：$BACKUP"
cp -a "$PANEL" "$BACKUP"

curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 --proto "=https" --tlsv1.2 -o "$TMP/panel.zip" "$URL"
[[ -s "$TMP/panel.zip" ]] || { echo "升级包为空。" >&2; exit 1; }

if [[ -n "$EXPECTED_SHA256" ]]; then
  [[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "EXPECTED_SHA256 格式错误。" >&2; exit 1; }
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
    if bad: raise SystemExit("归档包含不安全 ZIP 成员: " + repr(bad[:10]))
    if not any(name.endswith("panel/update.sh") for name in z.namelist()):
        raise SystemExit("压缩包中不存在 panel/update.sh；拒绝将其作为版本升级包执行。")
PY

mkdir -p "$TMP/unpacked"
unzip -q "$TMP/panel.zip" -d "$TMP/unpacked"
UPDATE_SCRIPT="$(find "$TMP/unpacked" -type f -path "*/panel/update.sh" -print -quit)"
[[ -n "$UPDATE_SCRIPT" ]] || { echo "解压后未找到 panel/update.sh。" >&2; exit 1; }

echo "升级前停止面板服务。"
systemctl stop bt-task.service bt.service 2>/dev/null || true
(
  cd "$(dirname "$UPDATE_SCRIPT")"
  bash ./update.sh
)

if [[ ! -f "$PANEL/BT-Panel" ]]; then
  echo "更新后 BT-Panel 缺失；保留备份于 $BACKUP，请人工恢复。" >&2
  exit 1
fi

systemctl daemon-reload
systemctl restart bt.service
sleep 5
if ! systemctl is-active --quiet bt.service; then
  journalctl -u bt.service -n 100 --no-pager >&2 || true
  echo "面板服务启动失败；原目录备份保留在 $BACKUP。" >&2
  echo "注意：更新程序可能已经执行数据库或配置迁移，不要未经检查直接覆盖回滚。" >&2
  exit 1
fi
systemctl restart bt-task.service 2>/dev/null || true

echo "版本升级脚本执行完成。备份目录：$BACKUP"
echo "请登录面板验证版本、页面、任务和插件功能。" 
