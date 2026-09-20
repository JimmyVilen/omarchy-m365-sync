"""Status for rclone-mount@<name>.service user units, printed as JSON for the bar widget."""
import glob
import http.client
import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

HOME = Path.home()
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
UNIT_DIR = HOME / ".config/systemd/user"
LOG_DIR = HOME / ".cache/rclone"
MOUNT_ROOT = HOME / "Preventia"

AUTH_PATTERN = re.compile(
  r"invalid_grant|InvalidAuthenticationToken|couldn't fetch token|token expired|AADSTS\d+|401 Unauthorized",
  re.IGNORECASE,
)
LOG_TS = re.compile(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) (ERROR|CRITICAL|NOTICE|INFO|DEBUG)\s*: (.*)$")
RECENT_SEC = 15 * 60


class UnixHTTPConnection(http.client.HTTPConnection):
  def __init__(self, path, timeout=2):
    super().__init__("localhost", timeout=timeout)
    self._path = path

  def connect(self):
    self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    self.sock.settimeout(self.timeout)
    self.sock.connect(self._path)


def rc_call(sock_path, method):
  if not os.path.exists(sock_path):
    return None
  try:
    conn = UnixHTTPConnection(sock_path)
    conn.request("POST", "/" + method, body="{}", headers={"Content-Type": "application/json"})
    response = conn.getresponse()
    if response.status != 200:
      return None
    return json.loads(response.read())
  except (OSError, ValueError, http.client.HTTPException):
    return None


def discover_units():
  names = set()
  for path in glob.glob(str(UNIT_DIR / "*.target.wants/rclone-mount@*.service")):
    names.add(Path(path).name[len("rclone-mount@"):-len(".service")])
  try:
    out = subprocess.run(
      ["systemctl", "--user", "list-units", "--all", "--plain", "--no-legend", "rclone-mount@*.service"],
      capture_output=True, text=True, timeout=3,
    ).stdout
    for line in out.splitlines():
      unit = line.split()[0] if line.split() else ""
      if unit.startswith("rclone-mount@") and unit.endswith(".service"):
        names.add(unit[len("rclone-mount@"):-len(".service")])
  except (OSError, subprocess.TimeoutExpired):
    pass
  return sorted(n for n in names if n)


def unit_state(unit):
  try:
    out = subprocess.run(
      ["systemctl", "--user", "show", unit, "--timestamp=unix",
       "-p", "ActiveState", "-p", "SubState", "-p", "UnitFileState", "-p", "ActiveEnterTimestamp"],
      capture_output=True, text=True, timeout=3,
    ).stdout
  except (OSError, subprocess.TimeoutExpired):
    return {}
  return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def mounted_targets():
  targets = {}
  try:
    with open("/proc/self/mounts", encoding="utf-8") as handle:
      for line in handle:
        parts = line.split()
        if len(parts) >= 3 and parts[2] == "fuse.rclone":
          targets[parts[1].replace("\\040", " ")] = parts[0]
  except OSError:
    pass
  return targets


def scan_log(name, since):
  """Recent error / auth problems from the tail of the mount log, ignoring anything before `since`."""
  path = LOG_DIR / f"{name}.log"
  result = {"authError": False, "lastError": "", "lastErrorTs": 0}
  try:
    with path.open("rb") as handle:
      handle.seek(0, os.SEEK_END)
      size = handle.tell()
      handle.seek(max(0, size - 96 * 1024))
      lines = handle.read().decode("utf-8", "replace").splitlines()
  except OSError:
    return result

  cutoff = max(time.time() - RECENT_SEC, since)
  for line in lines:
    match = LOG_TS.match(line)
    if not match:
      continue
    ts = time.mktime(time.strptime(match.group(1), "%Y/%m/%d %H:%M:%S"))
    level, message = match.group(2), match.group(3)
    if level in ("ERROR", "CRITICAL") and ts >= cutoff:
      result["lastError"] = message.strip()
      result["lastErrorTs"] = int(ts)
      if AUTH_PATTERN.search(message):
        result["authError"] = True
  return result


def mount_status(name, mounts):
  unit = f"rclone-mount@{name}.service"
  state = unit_state(unit)
  mountpoint = str(MOUNT_ROOT / name)
  sock = os.path.join(RUNTIME, f"rclone-{name}.sock")
  active = state.get("ActiveState") == "active"

  row = {
    "name": name,
    "unit": unit,
    "activeState": state.get("ActiveState", "unknown"),
    "subState": state.get("SubState", ""),
    "enabled": state.get("UnitFileState") == "enabled",
    "mountpoint": mountpoint,
    "mounted": mountpoint in mounts,
    "logPath": str(LOG_DIR / f"{name}.log"),
    "rc": False,
    "uploadsInProgress": 0,
    "uploadsQueued": 0,
    "erroredFiles": 0,
    "cacheBytes": 0,
    "outOfSpace": False,
    "transfers": [],
  }
  started = state.get("ActiveEnterTimestamp", "").lstrip("@")
  row.update(scan_log(name, int(started) if started.isdigit() else 0))

  if active:
    vfs = rc_call(sock, "vfs/stats")
    if vfs:
      disk = vfs.get("diskCache") or {}
      row["rc"] = True
      row["uploadsInProgress"] = int(disk.get("uploadsInProgress") or 0)
      row["uploadsQueued"] = int(disk.get("uploadsQueued") or 0)
      row["erroredFiles"] = int(disk.get("erroredFiles") or 0)
      row["cacheBytes"] = int(disk.get("bytesUsed") or 0)
      row["outOfSpace"] = bool(disk.get("outOfSpace"))
    core = rc_call(sock, "core/stats")
    if core:
      for item in core.get("transferring") or []:
        row["transfers"].append({
          "name": os.path.basename(str(item.get("name") or "")),
          "percentage": int(item.get("percentage") or 0),
          "size": int(item.get("size") or 0),
          # Uploads write to the remote (dstFs set); VFS reads only have srcFs.
          "direction": "up" if item.get("dstFs") else "down",
        })

  if not active or not row["mounted"]:
    row["state"] = "stopped"
  elif row["authError"]:
    row["state"] = "auth"
  elif row["erroredFiles"] > 0 or row["outOfSpace"]:
    row["state"] = "error"
  elif row["uploadsInProgress"] or row["uploadsQueued"] or any(t["direction"] == "up" for t in row["transfers"]):
    row["state"] = "syncing"
  else:
    row["state"] = "ok"
  return row


def main():
  mounts = mounted_targets()
  rows = [mount_status(name, mounts) for name in discover_units()]
  states = {row["state"] for row in rows}
  if not rows:
    overall = "none"
  elif "auth" in states:
    overall = "auth"
  elif states & {"stopped", "error"}:
    overall = "error"
  elif "syncing" in states:
    overall = "syncing"
  else:
    overall = "ok"
  print(json.dumps({
    "ok": True,
    "overall": overall,
    "pending": sum(r["uploadsInProgress"] + r["uploadsQueued"] for r in rows),
    "mounts": rows,
  }))


if __name__ == "__main__":
  main()
