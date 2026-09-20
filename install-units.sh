#!/usr/bin/env bash
# Install the rclone-mount@ systemd user unit and enable one instance per remote.
# Run after `omarchy plugin add`, on a machine where `rclone config` already has
# the remotes. The rclone config itself is never in this repo: it holds OAuth
# tokens.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit_dir="$HOME/.config/systemd/user"
unit="rclone-mount@.service"

mkdir -p "$unit_dir"

if [[ -e "$unit_dir/$unit" ]] && ! diff -q "$here/systemd/$unit" "$unit_dir/$unit" >/dev/null; then
  backup="$unit_dir/$unit.bak.$(date +%s)"
  cp -p "$unit_dir/$unit" "$backup"
  echo "Sparade befintlig unit som $backup"
fi

cp "$here/systemd/$unit" "$unit_dir/$unit"
systemctl --user daemon-reload
echo "Installerade $unit"

mapfile -t remotes < <(rclone listremotes 2>/dev/null | sed 's/:$//')
if (( ! ${#remotes[@]} )); then
  echo
  echo "Inga rclone-remotes hittades. Kör 'rclone config' och skapa dem först," >&2
  echo "aktivera sedan varje mount med:" >&2
  echo "  systemctl --user enable --now rclone-mount@<remote>.service" >&2
  exit 1
fi

echo
echo "Hittade remotes: ${remotes[*]}"
for remote in "${remotes[@]}"; do
  read -rp "Aktivera mount för '$remote'? [y/N] " answer
  [[ $answer == [yY] ]] || continue
  systemctl --user enable --now "rclone-mount@$remote.service"
  echo "  aktiverad: ~/Preventia/$remote"
done

echo
echo "Status:"
systemctl --user list-units 'rclone-mount@*' --all --no-pager

# Launched from the widget the script owns the terminal window, so hold it open
# long enough to read what happened.
if [[ -t 0 ]]; then
  echo
  read -rp "Tryck Enter för att stänga… " _
fi
