#!/usr/bin/env bash
set -u
P=/www/server/panel
echo "===== OS ====="; cat /etc/os-release 2>/dev/null || true; uname -a
echo "===== Panel files ====="; ls -ld "$P" "$P/BT-Panel" "$P/BT-Task" 2>&1 || true
echo "===== Python ====="; command -v python / python3 2>/dev/null || true; "$P/pyenv/bin/python" --version 2>&1 || true
echo "===== Services ====="; systemctl status bt.service bt-task.service --no-pager -l 2>&1 || true
echo "===== Port ====="; if [[ -r "$P/data/port.pl" ]]; then port=$(cat "$P/data/port.pl"); echo "Configured: $port"; ss -lntp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true; fi
echo "===== Panel logs ====="; tail -n 100 "$P/logs/error.log" 2>/dev/null || true
echo "===== systemd journal ====="; journalctl -u bt.service -u bt-task.service -n 100 --no-pager 2>&1 || true