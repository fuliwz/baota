#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# 宝塔 7.4.0 部署器（Ubuntu 24.04）
# 此脚本只在兼容性未经验证时完成预检和安全部署，不伪报启动成功。

RELEASE_TAG="v7.4.0"
DEFAULT_ARCHIVE_URL="https://github.com/fuliwz/baota/releases/download/${RELEASE_TAG}/LinuxPanel-7.4.0.zip"
PANEL_ARCHIVE_URL="${PANEL_ARCHIVE_URL:-${DEFAULT_ARCHIVE_URL}}"
PANEL_PORT="${PANEL_PORT:-8888}"
PANEL_INSTALL_DIR="${PANEL_INSTALL_DIR:-/www/server/panel}"
WORK_DIR="$(mktemp -d -t bt740-install.XXXXXX)"
ARCHIVE="${WORK_DIR}/panel.zip"
EXTRACT_DIR="${WORK_DIR}/extracted"
BACKUP_DIR=""

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

on_error() {
  local rc=$?
  printf '[ERROR] 安装器在第 %s 行失败（退出码 %s）。\n' "${BASH_LINENO[0]:-未知}" "$rc" >&2
  exit "$rc"
}
trap on_error ERR

[[ $EUID -eq 0 ]] || die "请使用 root 运行。"
command -v curl >/dev/null 2>&1 || die "缺少 curl。请先安装 curl。"

if [[ "${SKIP_OS_CHECK:-0}" != "1" ]]; then
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || die "仅允许 Ubuntu 24.04；检测到 ${PRETTY_NAME:-未知系统}。"
  case "$(dpkg --print-architecture)" in
    amd64|arm64) ;;
    *) die "当前架构暂不支持：$(dpkg --print-architecture)" ;;
  esac
fi

[[ "$PANEL_PORT" =~ ^[0-9]{1,5}$ ]] || die "PANEL_PORT 必须是 1-65535 的数字。"
(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) || die "PANEL_PORT 超出范围。"
[[ "$PANEL_INSTALL_DIR" == /www/server/panel ]] || die "当前版本固定安装目录为 /www/server/panel，避免误覆盖其他路径。"

log "系统预检通过。"
log "下载面板归档：$PANEL_ARCHIVE_URL"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 \
  --proto '=https' --tlsv1.2 -o "$ARCHIVE" "$PANEL_ARCHIVE_URL" \
  || die "下载失败。请确认 GitHub Release 资产已发布，或设置 PANEL_ARCHIVE_URL。"

[[ -s "$ARCHIVE" ]] || die "下载文件为空。"
command -v python3 >/dev/null 2>&1 || die "缺少 python3。"
mkdir -p "$EXTRACT_DIR"

# Validate archive member paths and reject symlinks before extraction.
python3 - "$ARCHIVE" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    bad = []
    for i in z.infolist():
        n = i.filename.replace("\\", "/")
        if n.startswith("/") or any(p == ".." for p in n.split("/")):
            bad.append(i.filename)
        mode = (i.external_attr >> 16) & 0o170000
        if mode == 0o120000:
            bad.append(i.filename)
    if bad:
        raise SystemExit("拒绝危险 ZIP 成员: " + ", ".join(bad[:10]))
PY
unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"

for f in panel/BT-Panel panel/BT-Task panel/requirements.txt; do
  [[ -f "$EXTRACT_DIR/$f" ]] || die "归档缺少必要文件：$f"
done

# 记录旧版启动与依赖特征，明确阻止未经验证的 Python 3.12 直接启动。
if head -n 1 "$EXTRACT_DIR/panel/BT-Panel" | grep -qE '^#!/usr/bin/python([[:space:]]|$)'; then
  warn "检测到旧式 /usr/bin/python shebang。Ubuntu 24.04 默认不提供该命令。"
fi
if grep -qE '^Pillow==5\.4\.1([[:space:]]|$)' "$EXTRACT_DIR/panel/requirements.txt"; then
  warn "检测到 Pillow 5.4.1；不能假定其可在 Python 3.12 上正常构建/运行。"
fi

log "归档结构检查通过。开始部署文件（不启动未经验证的旧版程序）。"
mkdir -p /www/server /www/wwwroot /www/wwwlogs /www/backup/database /www/backup/site

if [[ -e "$PANEL_INSTALL_DIR" ]]; then
  BACKUP_DIR="/www/server/panel.backup.$(date +%Y%m%d%H%M%S)"
  log "备份现有面板目录到：$BACKUP_DIR"
  mv "$PANEL_INSTALL_DIR" "$BACKUP_DIR"
fi

if ! cp -a "$EXTRACT_DIR/panel" "$PANEL_INSTALL_DIR"; then
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] && mv "$BACKUP_DIR" "$PANEL_INSTALL_DIR"
  die "复制面板文件失败；已尝试恢复原目录。"
fi

mkdir -p "$PANEL_INSTALL_DIR/logs"
printf '%s\n' "$PANEL_PORT" > "$PANEL_INSTALL_DIR/data/port.pl"
chmod 700 "$PANEL_INSTALL_DIR/BT-Panel" "$PANEL_INSTALL_DIR/BT-Task" || true
chmod 600 "$PANEL_INSTALL_DIR/data/port.pl"
chmod -R u+rwX,go-rwx "$PANEL_INSTALL_DIR"

cat <<EOF

============================================================
文件部署完成，但面板尚未启动。
============================================================
面板目录：$PANEL_INSTALL_DIR
预设端口：$PANEL_PORT
备份目录：${BACKUP_DIR:-无}
安装状态：FILES_DEPLOYED_NOT_STARTED

阻止启动的原因：
1. 原始启动器使用旧式 /usr/bin/python；
2. 原始依赖清单包含年代较早的二进制/源码依赖；
3. 尚未验证 Python 3.12 兼容性、初始化流程和任务进程行为。

下一步需要针对该 ZIP 完成依赖兼容性测试，再生成 systemd 服务。
请勿直接创建服务并启动，以免产生难以诊断的失败或破坏初始化数据。
============================================================
EOF
