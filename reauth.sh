#!/usr/bin/env bash
# Log in to Microsoft 365 again and give the new token to every OneDrive/SharePoint remote.
# Uses `rclone authorize` rather than `rclone config reconnect`, since reconnect re-runs the
# drive picker and can overwrite drive_id.
set -euo pipefail

conf="$(rclone config file | tail -n1)"

echo "Loggar in mot Microsoft 365 – en webbläsarflik öppnas."
echo
if ! out="$(rclone authorize onedrive)"; then
  echo "Inloggningen avbröts eller misslyckades."
  read -rp "Tryck Enter för att stänga… " _
  exit 1
fi

token="$(printf '%s\n' "$out" | sed -n '/--->/,/<---/p' | grep -o '{.*}' | tail -n1)"
if [[ -z "$token" ]]; then
  echo "Hittade ingen token i svaret från rclone."
  read -rp "Tryck Enter för att stänga… " _
  exit 1
fi

cp -p "$conf" "$conf.bak.$(date +%s)"
TOKEN="$token" python3 - "$conf" <<'EOF'
import configparser, os, sys
path = sys.argv[1]
config = configparser.RawConfigParser()
config.read(path)
updated = []
for section in config.sections():
  if config[section].get("type") == "onedrive":
    config[section]["token"] = os.environ["TOKEN"]
    updated.append(section)
with open(path, "w") as handle:
  config.write(handle)
os.chmod(path, 0o600)
print("Uppdaterade:", ", ".join(updated))
EOF

mapfile -t units < <(systemctl --user list-units --all --plain --no-legend 'rclone-mount@*.service' | awk '{print $1}')
if (( ${#units[@]} )); then
  echo "Startar om: ${units[*]}"
  systemctl --user restart "${units[@]}"
fi

echo
echo "Klart."
read -rp "Tryck Enter för att stänga… " _
