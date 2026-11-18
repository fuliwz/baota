#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# 宝塔 Linux Panel 7.4.0 自定义运行时安装器（开发分支）
# 首批运行时范围：systemd + CPython 3.10/3.11；未验证平台会拒绝启动。

RELEASE_TAG="v7.4.0"
REPO="fuliwz/baota"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
PANEL_ARCHIVE_URL="${PANEL_ARCHIVE_URL:-https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip}"
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

# Detect the distribution and package manager. This installer stages files only;
# it deliberately does not claim that this legacy panel runtime works everywhere.
OS_ID="unknown"
OS_VERSION="unknown"
OS_PRETTY="未知 Linux"
OS_LIKE=""
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
  OS_LIKE="${ID_LIKE:-}"
fi
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "当前 CPU 架构暂不支持：$ARCH（仅支持 x86_64/amd64/aarch64/arm64）。" ;;
esac

PKG_MANAGER=""
for pm in apt-get dnf yum zypper apk pacman; do
  if command -v "$pm" >/dev/null 2>&1; then PKG_MANAGER="$pm"; break; fi
done

install_prerequisites() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v python3 >/dev/null 2>&1 || missing+=(python3)
  command -v unzip >/dev/null 2>&1 || missing+=(unzip)
  if [[ -n "${EXPECTED_SHA256:-}" ]]; then
    command -v sha256sum >/dev/null 2>&1 || missing+=(sha256sum)
  fi
  if (("${#missing[@]}" == 0)); then return 0; fi
  [[ -n "$PKG_MANAGER" ]] || die "缺少必要命令：${missing[*]}；且未检测到受支持的包管理器，无法自动补齐。"
  log "使用 $PKG_MANAGER 安装必要工具：${missing[*]}"
  case "$PKG_MANAGER" in
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y ca-certificates curl python3 unzip coreutils
      ;;
    dnf) dnf install -y ca-certificates curl python3 unzip coreutils ;;
    yum) yum install -y ca-certificates curl python3 unzip coreutils ;;
    zypper) zypper --non-interactive refresh; zypper --non-interactive install --no-confirm ca-certificates curl python3 unzip coreutils ;;
    apk) apk add --no-cache ca-certificates curl python3 unzip coreutils ;;
    pacman) pacman -Sy --noconfirm --needed ca-certificates curl python unzip coreutils ;;
  esac
  command -v curl >/dev/null 2>&1 || die "安装依赖后仍缺少 curl。"
  command -v python3 >/dev/null 2>&1 || die "安装依赖后仍缺少 python3。"
  command -v unzip >/dev/null 2>&1 || die "安装依赖后仍缺少 unzip。"
}
install_prerequisites

log "检测到系统：$OS_PRETTY"
log "系统标识：$OS_ID $OS_VERSION；架构：$ARCH；包管理器：${PKG_MANAGER:-未检测到}"
log "安装器将继续执行 Python 版本、依赖、语法、服务和 HTTP 健康检查；未通过时会停止并尝试回滚。"

[[ "$PANEL_PORT" =~ ^[0-9]{1,5}$ ]] || die "PANEL_PORT 必须是 1-65535 的数字。"
(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) || die "PANEL_PORT 超出范围。"
[[ "$PANEL_INSTALL_DIR" == /www/server/panel ]] || die "当前版本固定安装目录为 /www/server/panel，避免误覆盖其他路径。"

log "系统预检通过。"
log "下载面板归档：$PANEL_ARCHIVE_URL"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 \
  --proto '=https' --tlsv1.2 -o "$ARCHIVE" "$PANEL_ARCHIVE_URL" \
  || die "下载失败。请确认 GitHub Release 资产已发布，或设置 PANEL_ARCHIVE_URL。"

[[ -s "$ARCHIVE" ]] || die "下载文件为空。"
if [[ -n "$EXPECTED_SHA256" ]]; then
  [[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || die "EXPECTED_SHA256 必须是 64 位十六进制 SHA256。"
  echo "$EXPECTED_SHA256  $ARCHIVE" | sha256sum --check --status || die "ZIP SHA256 校验失败。"
else
  warn "未设置 EXPECTED_SHA256。建议先核实源归档 SHA256，再固定校验值。"
fi
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

OLD_BT_ACTIVE=0
OLD_TASK_ACTIVE=0
if systemctl is-active --quiet bt.service 2>/dev/null; then OLD_BT_ACTIVE=1; fi
if systemctl is-active --quiet bt-task.service 2>/dev/null; then OLD_TASK_ACTIVE=1; fi
if [[ -e "$PANEL_INSTALL_DIR" ]]; then
  [[ -d "$PANEL_INSTALL_DIR" ]] || die "安装目标存在但不是目录，拒绝覆盖：$PANEL_INSTALL_DIR"
  log "检测到已有面板目录，先停止旧面板服务。"
  systemctl stop bt-task.service bt.service 2>/dev/null || true
  BACKUP_DIR="/www/server/panel.backup.$(date +%Y%m%d%H%M%S)"
  log "备份现有面板目录到：$BACKUP_DIR"
  mv "$PANEL_INSTALL_DIR" "$BACKUP_DIR"
fi

if ! cp -a "$EXTRACT_DIR/panel" "$PANEL_INSTALL_DIR"; then
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] && mv "$BACKUP_DIR" "$PANEL_INSTALL_DIR"
  die "复制面板文件失败；已尝试恢复原目录。"
fi

# Preserve user data and local configuration when replacing an existing tree.
if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
  for persistent in data config ssl logs plugin; do
    if [[ -e "$BACKUP_DIR/$persistent" ]]; then
      rm -rf "$PANEL_INSTALL_DIR/$persistent"
      cp -a "$BACKUP_DIR/$persistent" "$PANEL_INSTALL_DIR/$persistent"
    fi
  done
fi

mkdir -p "$PANEL_INSTALL_DIR/logs"
printf '%s\n' "$PANEL_PORT" > "$PANEL_INSTALL_DIR/data/port.pl"
chmod 700 "$PANEL_INSTALL_DIR/BT-Panel" "$PANEL_INSTALL_DIR/BT-Task" || true
chmod 600 "$PANEL_INSTALL_DIR/data/port.pl"
chmod -R u+rwX,go-rwx "$PANEL_INSTALL_DIR"

cat <<EOF

============================================================
面板文件部署完成，开始安装 Python 运行环境。
============================================================
面板目录：$PANEL_INSTALL_DIR
预设端口：$PANEL_PORT
备份目录：${BACKUP_DIR:-无}
安装阶段：文件部署完成

接下来将安装隔离的 Python 环境、执行语法和依赖检查，并配置 systemd 服务。
若运行时检查失败，安装器会尝试恢复原面板目录。
============================================================
EOF


# ---- Runtime installation layer (development branch) ----
PANEL_ROOT="$PANEL_INSTALL_DIR"
ASSET_DIR="$WORK_DIR/runtime-assets"
RUNTIME_RAW="https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev"
RUNTIME_BACKUP="$BACKUP_DIR"
RUNTIME_DEPLOYED=1
UNIT_BACKUP="$WORK_DIR/old-systemd-units"
mkdir -p "$UNIT_BACKUP"
for unit in bt.service bt-task.service; do
  [[ -f "/etc/systemd/system/$unit" ]] && cp -a "/etc/systemd/system/$unit" "$UNIT_BACKUP/$unit"
done
runtime_rollback() {
  local rc=$?
  trap - ERR
  if [[ $# -gt 0 ]]; then rc=$1; fi
  [[ "$rc" -ne 0 ]] || rc=1
  systemctl disable --now bt-task.service bt.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/bt.service /etc/systemd/system/bt-task.service
  cp -a "$UNIT_BACKUP/." /etc/systemd/system/ 2>/dev/null || true
  rm -f /usr/local/bin/bt-diagnose /usr/local/bin/bt-upgrade /usr/local/bin/bt-uninstall
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [[ "$RUNTIME_DEPLOYED" == 1 ]]; then
    rm -rf "$PANEL_ROOT"
    if [[ -n "$RUNTIME_BACKUP" && -d "$RUNTIME_BACKUP" ]]; then mv "$RUNTIME_BACKUP" "$PANEL_ROOT"; fi
  fi
  if [[ "$OLD_BT_ACTIVE" == 1 ]]; then systemctl start bt.service >/dev/null 2>&1 || true; fi
  if [[ "$OLD_TASK_ACTIVE" == 1 ]]; then systemctl start bt-task.service >/dev/null 2>&1 || true; fi
  printf '[ERROR] 运行环境安装失败，已尝试回滚面板目录（退出码 %s）。\n' "$rc" >&2
  exit "$rc"
}
trap runtime_rollback ERR
die(){ printf '[ERROR] %s\n' "$*" >&2; runtime_rollback 1; }

log "安装 Python 构建依赖和运行库。"
case "$PKG_MANAGER" in
  apt-get)
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y python3-venv python3-dev build-essential libssl-dev libffi-dev zlib1g-dev libjpeg-dev libxml2-dev libxslt1-dev libsqlite3-dev libbz2-dev libreadline-dev liblzma-dev ;;
  dnf|yum)
    "$PKG_MANAGER" install -y python3-devel gcc gcc-c++ make openssl-devel libffi-devel zlib-devel libjpeg-turbo-devel libxml2-devel libxslt-devel sqlite-devel bzip2-devel readline-devel xz-devel ;;
  zypper)
    zypper --non-interactive install --no-confirm python3-devel gcc gcc-c++ make libopenssl-devel libffi-devel zlib-devel libjpeg8-devel libxml2-devel libxslt-devel sqlite3-devel libbz2-devel readline-devel xz-devel ;;
  apk|pacman) die "该发行版的运行时构建依赖尚未验证；不会启动面板。";;
  *) die "无法为该包管理器安装运行时依赖。";;
esac

PYTHON_BIN="$(command -v python3)"
PYTHON_VERSION="$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
case "$PYTHON_VERSION" in 3.10|3.11) ;; *) die "当前 Python 为 $PYTHON_VERSION；首批运行时只接受 Python 3.10/3.11。";; esac
log "使用 Python $PYTHON_VERSION。"

mkdir -p "$ASSET_DIR"
for asset in scripts/patch_python3.py scripts/run_panel.py scripts/run_task.py requirements-py310.txt systemd/bt.service systemd/bt-task.service diagnose.sh upgrade.sh uninstall.sh; do
  mkdir -p "$ASSET_DIR/$(dirname "$asset")"
  curl --fail --location --retry 3 -o "$ASSET_DIR/$asset" "$RUNTIME_RAW/$asset"
done
python3 "$ASSET_DIR/scripts/patch_python3.py"

log "创建独立 Python 虚拟环境并安装锁定依赖。"
"$PYTHON_BIN" -m venv "$PANEL_ROOT/pyenv"
"$PANEL_ROOT/pyenv/bin/python" -m pip install --upgrade "pip<25" "setuptools<76" wheel
"$PANEL_ROOT/pyenv/bin/pip" install --prefer-binary -r "$ASSET_DIR/requirements-py310.txt"
"$PANEL_ROOT/pyenv/bin/pip" check

log "执行 Python 语法和关键依赖检查。"
"$PANEL_ROOT/pyenv/bin/python" - <<'PY'
import os
base="/www/server/panel"
errors=[]
for root, dirs, files in os.walk(base):
    dirs[:] = [d for d in dirs if d != "pyenv"]
    for name in files:
        if name.endswith(".py"):
            path=os.path.join(root,name)
            try:
                with open(path,"rb") as f: compile(f.read(),path,"exec")
            except Exception as e: errors.append((path,str(e)))
if errors:
    for path, err in errors: print(path, err)
    raise SystemExit("Python compile check failed: %d error(s)" % len(errors))
import flask, werkzeug, gevent, geventwebsocket.handler, flask_sockets, flask_compress, flask_sqlalchemy, PIL, paramiko, psutil, Crypto.Cipher.AES, dns.resolver, pymysql, libinjection, redis, rarfile, tldextract, libcloud, memcache
from OpenSSL import crypto
print("Python syntax and runtime dependency imports passed.")
PY

install -m 0755 "$ASSET_DIR/scripts/run_panel.py" "$PANEL_ROOT/BT-Panel-systemd.py"
install -m 0755 "$ASSET_DIR/scripts/run_task.py" "$PANEL_ROOT/run_task.py"
install -m 0644 "$ASSET_DIR/systemd/bt.service" /etc/systemd/system/bt.service
install -m 0644 "$ASSET_DIR/systemd/bt-task.service" /etc/systemd/system/bt-task.service
chmod -R u+rwX,go-rwx "$PANEL_ROOT"
systemctl daemon-reload
log "启动面板和任务服务。"
systemctl enable --now bt.service
sleep 3
systemctl is-active --quiet bt.service || { journalctl -u bt.service -n 80 --no-pager; die "面板服务启动失败。"; }
systemctl enable --now bt-task.service
sleep 2
systemctl is-active --quiet bt-task.service || { journalctl -u bt-task.service -n 80 --no-pager; die "任务服务启动失败。"; }
HEALTH_HOST="127.0.0.1"
[[ -f "$PANEL_ROOT/data/ipv6.pl" ]] && HEALTH_HOST="[::1]"
HEALTH_SCHEME="http"
HEALTH_CURL_ARGS=()
if [[ -f "$PANEL_ROOT/data/ssl.pl" && -f "$PANEL_ROOT/ssl/privateKey.pem" && -f "$PANEL_ROOT/ssl/certificate.pem" && ! -f "$PANEL_ROOT/data/debug.pl" ]]; then
  HEALTH_SCHEME="https"
  HEALTH_CURL_ARGS=(-k)
fi
curl --silent --show-error --max-time 10 "${HEALTH_CURL_ARGS[@]}" "$HEALTH_SCHEME://$HEALTH_HOST:$PANEL_PORT/service_status" | grep -q True || {
  journalctl -u bt.service -n 80 --no-pager
  die "面板健康检查失败。"
}
RUNTIME_DEPLOYED=0
trap on_error ERR
echo "安装完成：$PANEL_ROOT；Python：$("$PANEL_ROOT/pyenv/bin/python" --version 2>&1)"
echo "访问地址：http://服务器IP:$PANEL_PORT；旧目录备份：$RUNTIME_BACKUP"
echo "服务：$(systemctl is-active bt.service) / $(systemctl is-active bt-task.service)"
echo "日志：journalctl -u bt -u bt-task -n 100 --no-pager"
echo "云厂商安全组需自行放行 TCP $PANEL_PORT；安装器不会猜测默认管理员密码。"
