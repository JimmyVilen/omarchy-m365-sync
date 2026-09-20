import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property string overall: "none"
  property int pending: 0
  property var mounts: []
  property var transfers: []
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 5, 600)
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/status.py"
  readonly property string mountRoot: Quickshell.env("HOME") + "/Preventia"
  readonly property bool busy: statusProcess.running

  property string _statusOutput: ""
  property string _statusError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Kunde inte läsa rclone-status"
      return
    }
    overall = String(parsed.overall || "none")
    pending = Number(parsed.pending || 0)
    mounts = parsed.mounts
    transfers = Model.allTransfers(parsed.mounts)
    lastError = ""
  }

  function flash(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  function openFolder(mount) {
    var path = mount ? mount.mountpoint : mountRoot
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", path])
  }

  function restart(mount) {
    if (!mount) return
    Quickshell.execDetached(["systemctl", "--user", "restart", mount.unit])
    flash("Startar om " + mount.name + "…")
    settleTimer.ticks = 0
    settleTimer.restart()
  }

  function showLog(mount) {
    if (!mount) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "tail", "-n", "200", "-F", mount.logPath])
  }

  function reauth() {
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", pluginDir + "/reauth.sh"])
    flash("Inloggning startad i terminalen")
    settleTimer.ticks = 0
    settleTimer.restart()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2500
    onTriggered: root.actionStatus = ""
  }

  Timer {
    // Mounts take a few seconds to come back after a restart or re-login.
    id: settleTimer
    property int ticks: 0
    interval: 2000
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 8) running = false
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = (stderr || stdout || "Kunde inte läsa rclone-status").trim().substring(0, 140)
    }
  }
}
