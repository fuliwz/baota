#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# 宝塔 Linux Panel 7.4.0 一键安装器
# 重要：LinuxPanel-7.4.0.zip 是离线升级包，不是全新安装源码。
BASE_INSTALLER_URL="${BASE_INSTALLER_URL:-https://download.bt.cn/install/install_6.0.sh}"
RELEASE_ARCHIVE_URL="${RELEASE_ARCHIVE_URL:-https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip}"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
PANEL_PORT="${PANEL_PORT:-8888}"
TMP="$(mktemp -d -t bt740-bootstrap.XXXXXX)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT
die(){ echo "[错误] $*" >&2; exit 1; }
log(){ echo "[宝塔7.4.0安装器] $*"; }

[[ $EUID -eq 0 ]] || die "请使用 root 运行。" 
[[ "$PANEL_PORT" =~ ^[0-9]{1,5}$ ]] && ((PANEL_PORT>=1 && PANEL_PORT<=65535)) || die "PANEL_PORT 必须为 1-65535。" 
[[ -r /etc/os-release ]] || die "无法识别 Linux 发行版。" 
. /etc/os-release
ARCH="$(uname -m)"
case "$ARCH" in x86_64|aarch64) ;; *) die "暂不支持架构：$ARCH";; esac
command -v systemctl >/dev/null 2>&1 || die "此安装器要求 systemd。" 

if ! command -v curl >/dev/null 2>&1; then
  case "${ID:-}" in
    ubuntu|debian) apt-get update; apt-get install -y curl ca-certificates ;;
    rhel|centos|rocky|almalinux|fedora) (dnf install -y curl ca-certificates || yum install -y curl ca-certificates) ;;
    *) die "缺少 curl，请先通过系统包管理器安装。" ;;
  esac
fi
command -v unzip >/dev/null 2>&1 || {
  case "${ID:-}" in
    ubuntu|debian) apt-get update; apt-get install -y unzip ;;
    rhel|centos|rocky|almalinux|fedora) (dnf install -y unzip || yum install -y unzip) ;;
    *) die "缺少 unzip，请先通过系统包管理器安装。" ;;
  esac
}

if [[ -e /www/server/panel ]]; then
  [[ -f /www/server/panel/BT-Panel ]] || die "检测到 /www/server/panel，但不是完整的已安装面板，拒绝覆盖。" 
  die "检测到已有宝塔面板。全新安装入口不会覆盖已有面板；请使用版本切换工具。" 
fi

log "第一阶段：执行宝塔基础安装脚本。" 
curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 --proto "=https" --tlsv1.2 -o "$TMP/base-install.sh" "$BASE_INSTALLER_URL"
[[ -s "$TMP/base-install.sh" ]] || die "基础安装脚本下载为空。" 
bash "$TMP/base-install.sh"

[[ -f /www/server/panel/BT-Panel && -f /www/server/panel/BT-Task ]] || die "基础安装脚本结束后未检测到完整面板文件。" 

log "第二阶段：下载 7.4.0 离线升级包。" 
curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 --proto "=https" --tlsv1.2 -o "$TMP/LinuxPanel-7.4.0.zip" "$RELEASE_ARCHIVE_URL"
[[ -s "$TMP/LinuxPanel-7.4.0.zip" ]] || die "7.4.0 ZIP 下载为空。" 
if [[ -n "$EXPECTED_SHA256" ]]; then
  [[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || die "EXPECTED_SHA256 格式错误。" 
  echo "$EXPECTED_SHA256  $TMP/LinuxPanel-7.4.0.zip" | sha256sum --check --status || die "升级包 SHA256 校验失败。" 
else
  log "警告：未设置 EXPECTED_SHA256，请在生产环境固定独立核实的 SHA256。" 
fi

python3 - "$TMP/LinuxPanel-7.4.0.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    bad=[]
    for item in z.infolist():
        name=item.filename.replace("\\","/")
        if name.startswith("/") or ".." in name.split("/"): bad.append(name)
        if ((item.external_attr >> 16) & 0o170000) == 0o120000: bad.append(name)
    if bad: raise SystemExit("ZIP 包含危险路径或符号链接: " + repr(bad[:10]))
    if not any(n.endswith("panel/update.sh") for n in z.namelist()):
        raise SystemExit("ZIP 中不存在 panel/update.sh，不是预期的面板升级包。")
PY
mkdir -p "$TMP/release"
unzip -q "$TMP/LinuxPanel-7.4.0.zip" -d "$TMP/release"
UPDATE_SCRIPT="$(find "$TMP/release" -type f -path "*/panel/update.sh" -print -quit)"
[[ -n "$UPDATE_SCRIPT" ]] || die "解压后找不到 panel/update.sh。" 

log "第三阶段：执行升级包自带的 update.sh。" 
systemctl stop bt-task.service bt.service 2>/dev/null || true
(
  cd "$(dirname "$UPDATE_SCRIPT")"
  bash ./update.sh
)

[[ -f /www/server/panel/BT-Panel ]] || die "update.sh 完成后未检测到 BT-Panel。" 
printf "%s\n" "$PANEL_PORT" > /www/server/panel/data/port.pl
chmod 600 /www/server/panel/data/port.pl

log "第四阶段：启动并检查面板服务。" 
systemctl daemon-reload
systemctl enable bt.service >/dev/null 2>&1 || true
systemctl restart bt.service
sleep 5
systemctl is-active --quiet bt.service || { journalctl -u bt.service -n 100 --no-pager; die "7.4.0 面板服务启动失败。" ; }
systemctl enable bt-task.service >/dev/null 2>&1 || true
systemctl restart bt-task.service 2>/dev/null || true
PORT="$(cat /www/server/panel/data/port.pl)"
ss -lnt 2>/dev/null | grep -E "[:.]${PORT}[[:space:]]" >/dev/null || { journalctl -u bt.service -n 100 --no-pager; die "面板端口没有监听。" ; }

echo
echo "============================================================"
echo "宝塔 Linux Panel 7.4.0 安装/版本切换流程已执行完成"
echo "============================================================"
echo "面板目录：/www/server/panel"
echo "访问端口：$PORT"
echo "服务状态：$(systemctl is-active bt.service)"
echo "安装账号及初始密码：请查看基础安装器输出及面板安装信息文件。"
echo "日志：journalctl -u bt -n 100 --no-pager"
echo "请在云厂商安全组放行 TCP $PORT。"
echo "============================================================"
