# cloud-mounts

Omarchy bar widget showing the state of `rclone-mount@` systemd user units —
mounted or not, pending uploads, and login problems — plus the systemd unit that
does the mounting.

Today the mounts are Microsoft 365 (OneDrive / SharePoint), which is what the
panel header says. The plugin id is deliberately broader than that, so other
backends can be added later without renaming anything.

## Install on a new machine

```bash
omarchy plugin add git@github.com:JimmyVilen/omarchy-m365-sync.git --enable
```

That installs the widget as `io.github.jimmyvilen.cloud-mounts`. It will show
"no mounts" until the systemd side exists too:

```bash
# 1. Create the remotes (opens a browser for the M365 login)
rclone config

# 2. Install the unit and enable one instance per remote
~/.config/omarchy/plugins/io.github.jimmyvilen.cloud-mounts/install-units.sh
```

## What is where

| Path | Purpose |
| --- | --- |
| `manifest.json`, `Panel.qml`, `Service.qml`, `Model.js` | the bar widget |
| `status.py` | reads mount state and pending uploads via each mount's rclone rc socket |
| `reauth.sh` | re-runs the M365 login and writes the new token to every `onedrive` remote |
| `systemd/rclone-mount@.service` | the template unit, one instance per remote |
| `systemd/mount-IT.env.example` | optional per-mount flags, copy to `~/.config/rclone/mount-<remote>.env` |
| `install-units.sh` | copies the unit into place and enables instances |

## Not in this repo

`~/.config/rclone/rclone.conf` holds the OAuth tokens for every remote. It never
goes in git — `.gitignore` refuses it. On a new machine the tokens are created
fresh by `rclone config`, or refreshed later from the widget's "Logga in igen".

## The unit

`rclone-mount@<remote>.service` mounts `<remote>:` at `~/Preventia/<remote>` with
a full VFS cache (50G, 30 days) under `~/.cache/rclone`. Each instance opens an
rclone rc socket at `$XDG_RUNTIME_DIR/rclone-<remote>.sock`, which is how
`status.py` asks it about transfers — so that flag is load-bearing, not optional.

Per-mount flags go in `~/.config/rclone/mount-<remote>.env` as `RCLONE_EXTRA=…`;
the unit reads it if present and ignores it if not. The IT mount uses
`--ignore-size --ignore-checksum`, which SharePoint needs.

## Updating

```bash
omarchy plugin update io.github.jimmyvilen.cloud-mounts
```

Changes to the unit are *not* applied by that — rerun `install-units.sh` (it
backs up the old unit) and `systemctl --user restart rclone-mount@<remote>`.
