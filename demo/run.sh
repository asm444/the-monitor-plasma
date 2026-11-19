#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
for u in the-monitor.service the-monitor-coletor.service; do
  if systemctl --user is-active --quiet "$u"; then
    echo "pare $u antes (systemctl --user stop $u): ele grava o mesmo estado.json" >&2
    exit 1
  fi
done
trap 'kill 0' EXIT
python3 -I coletor.py --demo &
THE_MONITOR_CONFIG="$PWD/demo/config.toml" python3 -I hub.py &
echo "DEMO rodando com dados sintéticos; Ctrl-C encerra"
wait
