import QtQuick
import Quickshell
import Quickshell.Io

// Live coding-agent sessions, as reported by bin/agent-sessions.
QtObject {
  id: root

  property var settings: ({})
  property string pluginDir: ""

  property var sessions: []
  property bool loading: false
  property string lastError: ""

  readonly property int doneWindowSec: settings && settings.doneWindowSec ? settings.doneWindowSec : 300

  readonly property var blocked: sessions.filter(function (s) { return s.state === "blocked" })
  readonly property var working: sessions.filter(function (s) { return s.state === "working" })
  readonly property var done: sessions.filter(function (s) { return s.state === "done" })
  readonly property var idle: sessions.filter(function (s) { return s.state === "idle" })

  readonly property int count: sessions.length

  // One entry per agent kind present, e.g. [{agent: "claude", count: 3}, …].
  // The widget never hardcodes the list: it is whatever the collectors found.
  readonly property var byAgent: {
    var seen = {}
    var out = []
    for (var i = 0; i < sessions.length; i++) {
      var a = sessions[i].agent || "agent"
      if (seen[a] === undefined) { seen[a] = out.length; out.push({agent: a, count: 0}) }
      out[seen[a]].count += 1
    }
    return out
  }
  // What the bar colours on: a blocked session is the only one asking for you.
  readonly property bool needsAttention: blocked.length > 0

  signal refreshed()

  function script(name) {
    return pluginDir + "/bin/" + name
  }

  function refresh() {
    if (listProc.running) return
    loading = true
    listProc.command = [root.script("agent-sessions")]
    listProc.environment = ({ DONE_WINDOW_SEC: String(root.doneWindowSec) })
    listProc.running = true
  }

  // A herdr-hosted session has no window of its own, so it is addressed by its
  // pane instead of by a pid.
  function focus(entry) {
    if (!entry) return
    var pid = entry.pid ? String(entry.pid) : ""
    var pane = entry.paneId ? String(entry.paneId) : ""
    if (!pid && !pane) return
    focusProc.command = [root.script("focus-session"), pid, pane]
    focusProc.running = true
  }

  function copyText(value) {
    if (!value) return
    copyProc.command = ["bash", "-lc", "printf %s " + shellQuote(value) + " | wl-copy"]
    copyProc.running = true
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function stateLabel(state) {
    if (state === "blocked") return "blocked"
    if (state === "working") return "working"
    if (state === "done") return "done"
    return "idle"
  }

  function ageText(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    if (s < 60) return s + "s"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h " + (m % 60) + "m"
    return Math.floor(h / 24) + "d " + (h % 24) + "h"
  }

  property Process _listProc: Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        try {
          var list = JSON.parse(text)
          root.sessions = Array.isArray(list) ? list : []
          root.lastError = ""
        } catch (e) {
          root.sessions = []
          root.lastError = "agent-sessions returned no usable JSON"
        }
        root.refreshed()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: root.loading = false
  }

  property Process _focusProc: Process {
    id: focusProc
  }

  property Process _copyProc: Process {
    id: copyProc
  }
}
