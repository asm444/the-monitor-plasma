#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
umask 077

coletor=0
for arg in "$@"; do
  case "$arg" in
    --coletor) coletor=1 ;;
    *) echo "uso: $0 [--coletor]" >&2; exit 2 ;;
  esac
done

app=~/.local/share/the-monitor
rm -rf "$app.novo"
mkdir -p "$app.novo"
cp -r hub.py coletor.py monitor agentes "$app.novo/"
find "$app.novo" -name __pycache__ -prune -exec rm -rf {} +
rm -rf "$app"
mv "$app.novo" "$app"

mkdir -p ~/.config/the-monitor ~/.cache/the-monitor
chmod 700 ~/.config/the-monitor ~/.cache/the-monitor
[ -f ~/.config/the-monitor/config.toml ] || install -m600 config.example.toml ~/.config/the-monitor/config.toml

pacote=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}")
trap 'rm -rf "$pacote"' EXIT
cp -r the-monitor "$pacote/pkg"
chmod -R go+rX "$pacote/pkg"
kpackagetool6 -t Plasma/Applet -u "$pacote/pkg" 2>/dev/null || kpackagetool6 -t Plasma/Applet -i "$pacote/pkg"
rm -rf ~/.cache/plasmashell/qmlcache

unidades=(the-monitor.service)
[ "$coletor" = 1 ] && unidades+=(the-monitor-coletor.service)
for u in "${unidades[@]}"; do
  install -Dm644 "$u" ~/.config/systemd/user/"$u"
done
systemctl --user daemon-reload
systemctl --user enable --now "${unidades[@]}"
systemctl --user restart "${unidades[@]}"
echo "INSTALADO: ${unidades[*]} e o plasmoid org.asm.themonitor; adicione o widget \"The Monitor\" ao painel"
