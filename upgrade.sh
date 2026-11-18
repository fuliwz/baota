#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
P=/www/server/panel
[[ -d "$P" && -x "$P/pyenv/bin/python" ]] || { echo "未找到已安装的面板虚拟环境。" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "需要 systemd。" >&2; exit 1; }

STAMP=$(date +%Y%m%d%H%M%S)
BACKUP="/www/server/panel.runtime-backup.$STAMP"
UNIT_BACKUP="/root/bt-units-backup.$STAMP"
TMP=$(mktemp -d -t bt740-upgrade.XXXXXX)
SUCCESS=0

rollback() {
  rc=$?
  if [[ "$SUCCESS" != 1 ]]; then
    systemctl stop bt-task bt >/dev/null 2>&1 || true
    rm -rf "$P"
    [[ -d "$BACKUP" ]] && mv "$BACKUP" "$P"
    if [[ -d "$UNIT_BACKUP" ]]; then
      cp -a "$UNIT_BACKUP/." /etc/systemd/system/
      systemctl daemon-reload
    fi
    systemctl start bt >/dev/null 2>&1 || true
    systemctl start bt-task >/dev/null 2>&1 || true
    echo "升级失败，已尝试恢复面板和 systemd 服务；备份：$BACKUP" >&2
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap rollback ERR

mkdir -p "$UNIT_BACKUP"
cp -a /etc/systemd/system/bt.service /etc/systemd/system/bt-task.service "$UNIT_BACKUP/" 2>/dev/null || true
echo "正在备份当前面板：$BACKUP"
cp -a "$P" "$BACKUP"

RAW="https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev"
for asset in scripts/patch_python3.py scripts/run_panel.py scripts/run_task.py requirements-py310.txt systemd/bt.service systemd/bt-task.service; do
  mkdir -p "$TMP/$(dirname "$asset")"
  curl --fail --location --retry 3 -o "$TMP/$asset" "$RAW/$asset"
done

systemctl stop bt-task bt
python3 "$TMP/scripts/patch_python3.py"
"$P/pyenv/bin/pip" install --prefer-binary -r "$TMP/requirements-py310.txt"
"$P/pyenv/bin/python" - <<'PY'
import os
base="/www/server/panel"
bad=[]
for root, dirs, files in os.walk(base):
    dirs[:] = [d for d in dirs if d != "pyenv"]
    for name in files:
        if name.endswith(".py"):
            p=os.path.join(root,name)
            try:
                with open(p,"rb") as f: compile(f.read(),p,"exec")
            except Exception as e: bad.append((p,str(e)))
if bad:
    for p,e in bad: print(p,e)
    raise SystemExit("Python compile check failed")
import flask, werkzeug, gevent, flask_sockets, flask_compress, flask_sqlalchemy, PIL, paramiko, psutil
print("Runtime checks passed.")
PY
install -m 0755 "$TMP/scripts/run_panel.py" "$P/run_panel.py"
install -m 0755 "$TMP/scripts/run_task.py" "$P/run_task.py"
install -m 0644 "$TMP/systemd/bt.service" /etc/systemd/system/bt.service
install -m 0644 "$TMP/systemd/bt-task.service" /etc/systemd/system/bt-task.service
systemctl daemon-reload
systemctl start bt
sleep 3
systemctl is-active --quiet bt || { journalctl -u bt -n 80 --no-pager; false; }
systemctl start bt-task
sleep 2
systemctl is-active --quiet bt-task || { journalctl -u bt-task -n 80 --no-pager; false; }
PORT=$(cat "$P/data/port.pl")
curl --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/service_status" | grep -q True
SUCCESS=1
rm -rf "$TMP"
trap - ERR
echo "运行环境升级完成。"
echo "备份目录：$BACKUP"
echo "注意：此脚本更新运行时补丁、依赖锁和 systemd 启动器，不会更换宝塔面板主版本源码。"
