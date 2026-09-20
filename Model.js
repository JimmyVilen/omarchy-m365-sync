// Material Design Icons (Nerd Font) code points.
var GLYPH_OK = String.fromCodePoint(0xF0160)        // cloud-check
var GLYPH_SYNC = String.fromCodePoint(0xF0167)      // cloud-upload
var GLYPH_ERROR = String.fromCodePoint(0xF09E0)     // cloud-alert
var GLYPH_OFF = String.fromCodePoint(0xF0164)       // cloud-off-outline
var GLYPH_CLOUD = String.fromCodePoint(0xF015F)     // cloud
var GLYPH_FOLDER = String.fromCodePoint(0xF0770)    // folder-open
var GLYPH_RESTART = String.fromCodePoint(0xF0709)   // restart
var GLYPH_LOG = String.fromCodePoint(0xF0219)       // file-document
var GLYPH_LOGIN = String.fromCodePoint(0xF0342)     // login
var GLYPH_SETUP = String.fromCodePoint(0xF0493)     // cog
var GLYPH_UP = String.fromCodePoint(0xF005D)        // arrow-up
var GLYPH_DOWN = String.fromCodePoint(0xF0045)      // arrow-down

function defaultStatus() {
  return { ok: true, overall: "none", pending: 0, mounts: [] }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    parsed.mounts = Array.isArray(parsed.mounts) ? parsed.mounts : []
    return parsed
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Kunde inte läsa rclone-status"
    return failed
  }
}

function stateGlyph(state) {
  if (state === "ok") return GLYPH_OK
  if (state === "syncing") return GLYPH_SYNC
  if (state === "auth" || state === "error") return GLYPH_ERROR
  if (state === "stopped") return GLYPH_OFF
  return GLYPH_CLOUD
}

function overallText(status) {
  var s = status.overall
  if (s === "ok") return "Allt synkat"
  if (s === "syncing") return status.pending > 0 ? "Laddar upp " + status.pending + (status.pending === 1 ? " fil" : " filer") : "Laddar upp…"
  if (s === "auth") return "Inloggningen har gått ut"
  if (s === "error") return "Problem med en montering"
  return "Inga monteringar"
}

function mountMeta(m) {
  if (!m) return ""
  if (m.state === "stopped") return m.activeState === "failed" ? "Stoppad (fel)" : "Inte monterad"
  if (m.state === "auth") return "Inloggningen har gått ut – logga in igen"
  var parts = []
  var pending = Number(m.uploadsInProgress || 0) + Number(m.uploadsQueued || 0)
  if (pending > 0) parts.push(pending + " att ladda upp")
  var downloads = (m.transfers || []).filter(function(t) { return t.direction === "down" }).length
  if (downloads > 0) parts.push("hämtar " + downloads)
  if (Number(m.erroredFiles || 0) > 0) parts.push(m.erroredFiles + " misslyckade")
  if (m.outOfSpace) parts.push("cachen full")
  if (parts.length === 0) parts.push("Synkad")
  if (m.rc) parts.push("cache " + formatBytes(m.cacheBytes))
  return parts.join(" · ")
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function allTransfers(mounts) {
  var rows = []
  for (var i = 0; i < mounts.length; i++) {
    var list = mounts[i].transfers || []
    for (var j = 0; j < list.length; j++) {
      rows.push({ mount: mounts[i].name, name: list[j].name, percentage: list[j].percentage, size: list[j].size, direction: list[j].direction })
    }
  }
  // Uploads first — they are what must finish before shutting down.
  rows.sort(function(a, b) { return (a.direction === "up" ? 0 : 1) - (b.direction === "up" ? 0 : 1) })
  return rows
}
