#!/usr/bin/env bash
P=/www/server/panel
echo "===== OS ====="; cat /etc/os-release 2>/dev/null; uname -a
echo "===== Python ====="; "$P/pyenv/bin/python" --version 2>&1 || true
echo "===== Services ====="; systemctl status bt bt-task --no-pager -l 2>&1 || true
echo "===== Port ====="; test -r "$P/data/port.pl" && { p=$(cat "$P/data/port.pl"); echo "$p"; ss -lntp 2>/dev/null | grep ":$p " || true; }
echo "===== Journal ====="; journalctl -u bt -u bt-task -n 100 --no-pager 2>&1 || true
echo "===== Error log ====="; tail -n 80 "$P/logs/error.log" 2>/dev/null || true
