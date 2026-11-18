#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Download the Baota base installer only; apply 7.4.0 later via its own update.sh.
BASE_INSTALLER_URL="${BASE_INSTALLER_URL:-https://download.bt.cn/install/install_6.0.sh}"
TMP="$(mktemp -d -t bt-base-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
[[ -r /etc/os-release ]] || { echo "无法识别 Linux 系统。" >&2; exit 1; }
. /etc/os-release
case "$(uname -m)" in x86_64|aarch64) ;; *) echo "暂不支持当前 CPU 架构。" >&2; exit 1;; esac
command -v systemctl >/dev/null 2>&1 || { echo "该安装器要求 systemd。" >&2; exit 1; }

if [[ -e /www/server/panel ]]; then
  echo "检测到已有面板，拒绝覆盖；请使用独立的版本切换脚本。" >&2
  exit 1
fi

case "${ID:-}" in
  ubuntu|debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates
    ;;
  rhel|centos|rocky|almalinux|fedora)
    (dnf install -y curl ca-certificates || yum install -y curl ca-certificates)
    ;;
  opensuse*|sles)
    zypper --non-interactive install --no-confirm curl ca-certificates
    ;;
  *)
    echo "当前发行版尚未列入基础安装引导测试范围：${ID:-unknown}" >&2
    exit 1
    ;;
esac

echo "[宝塔安装器] 下载官方基础安装脚本：$BASE_INSTALLER_URL"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 --proto "=https" --tlsv1.2 -o "$TMP/base-install.sh" "$BASE_INSTALLER_URL"
[[ -s "$TMP/base-install.sh" ]] || { echo "基础安装脚本为空。" >&2; exit 1; }

echo "[宝塔安装器] 即将执行下载的基础安装脚本。"
echo "请注意：这是宝塔官方在线安装入口；它安装的初始面板版本由上游脚本决定。" 
echo "安装完成后，请使用 upgrade.sh 切换到 7.4.0；本脚本不会把离线升级包当成完整源码覆盖。" 
bash "$TMP/base-install.sh"

[[ -f /www/server/panel/BT-Panel ]] || { echo "基础安装脚本结束，但未找到 BT-Panel；请检查其输出。" >&2; exit 1; }
echo
echo "基础面板安装已完成。"
echo "下一步：使用本仓库 upgrade.sh 通过 7.4.0 离线升级包执行面板版本切换。" 
echo "请先查看官方升级说明和 VPS 快照，再进行版本切换。" 
