import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wseubring.sessions"
  ipcTarget: "wseubring.sessions"
  manageIpc: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
  readonly property int refreshIntervalSec: Math.max(1, setting("refreshIntervalSec", 5))
  readonly property bool showLabel: setting("showLabel", true) !== false
  // groups | dots | count | minimal — see README for the trade-offs.
  readonly property string indicatorStyle: String(setting("indicatorStyle", "groups"))
  readonly property int maxDots: Math.max(1, setting("maxDots", 6))
  readonly property bool animateWorking: setting("animateWorking", true) !== false
  readonly property bool showIdleGroup: setting("showIdleGroup", false) === true
  readonly property bool pulseBlocked: setting("pulseBlocked", true) !== false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The whole widget leaves the bar when no agent is running.
  visible: sessions.count > 0

  property int rowIndex: 0
  property bool cursorActive: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Mark per agent kind. Only the ones with a glyph everyone has are drawn as
  // icons; anything else falls back to the first letters of its name, so a new
  // collector is legible on day one without hunting for a codepoint. Override
  // with the agentGlyphs setting: {"codex": "\u{f0169}"}.
  readonly property var agentGlyphs: ({
    claude: "\u{f06a9}",
    pi: "\u03c0"
  })

  function agentGlyph(agent) {
    var custom = setting("agentGlyphs", null)
    if (custom && custom[agent]) return String(custom[agent])
    if (agentGlyphs[agent]) return agentGlyphs[agent]
    return String(agent).substring(0, 2)
  }

  function stateGlyph(state) {
    if (state === "blocked") return "󰀦"
    if (state === "working") return "●"
    if (state === "done") return "󰄬"
    return "○"
  }

  function stateColor(state) {
    if (state === "blocked") return root.urgent
    if (state === "working") return root.foreground
    if (state === "done") return root.foreground
    return root.dim
  }

  // ---- bar indicator ----------------------------------------------------
  // The bar has to stay legible with one agent and with ten, so the label is
  // built from state counts rather than from the sessions themselves; only the
  // "dots" style scales with the session count, and it caps itself.

  readonly property var spinnerFrames: ["◐", "◓", "◑", "◒"]
  property int spinnerFrame: 0

  // Working sessions get a turning glyph, so a glance says "something is live"
  // without reading the number.
  readonly property string workingGlyph: animateWorking && sessions.working.length > 0
    ? spinnerFrames[spinnerFrame % 4]
    : "●"

  function paint(text, color) {
    return "<font color=\"" + String(color) + "\">" + text + "</font>"
  }

  // Idle is the resting state of every session, so counting it earns no width
  // in the bar unless it is the only thing left to say.
  function groupsLabel() {
    var parts = []
    if (sessions.blocked.length > 0) parts.push(paint("󰀦" + sessions.blocked.length, root.urgent))
    if (sessions.working.length > 0) parts.push(paint(workingGlyph + sessions.working.length, root.foreground))
    if (sessions.done.length > 0) parts.push(paint("󰄬" + sessions.done.length, root.foreground))
    if (root.showIdleGroup || parts.length === 0)
      parts.push(paint("○" + sessions.idle.length, root.dim))
    return "󰚩 " + parts.join("  ")
  }

  function dotsLabel() {
    var out = []
    var shown = Math.min(sessions.count, root.maxDots)
    for (var i = 0; i < shown; i++) {
      var s = sessions.sessions[i]
      var glyph = s.state === "working" ? workingGlyph : root.stateGlyph(s.state)
      out.push(paint(glyph, root.stateColor(s.state)))
    }
    if (sessions.count > shown) out.push(paint("+" + (sessions.count - shown), root.dim))
    // Thin spaces: the glyphs merge into a smear when they sit flush.
    return "󰚩 " + out.join("&#8202;")
  }

  function minimalLabel() {
    // One glyph, coloured by the state that most deserves your attention.
    if (sessions.blocked.length > 0) return paint("󰚩", root.urgent)
    if (sessions.working.length > 0) return paint("󰚩", root.foreground)
    return paint("󰚩", root.dim)
  }

  function barLabel() {
    if (root.vertical || !root.showLabel) return "󰚩"
    if (root.indicatorStyle === "minimal") return minimalLabel()
    if (root.indicatorStyle === "dots") return dotsLabel()
    if (root.indicatorStyle === "count")
      return sessions.blocked.length > 0
        ? "󰚩  " + sessions.blocked.length + "!"
        : "󰚩  " + sessions.count
    return groupsLabel()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    rowIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    sessions.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0 || sessions.count === 0) return
    rowIndex = Math.max(0, Math.min(sessions.count - 1, rowIndex + dy))
    scrollCursorIntoView()
  }

  function activateCursor() {
    var entry = sessions.sessions[rowIndex]
    if (entry) root.focusSession(entry)
  }

  function scrollCursorIntoView() {
    if (!panelFlick || !sessionColumn) return
    var item = sessionColumn.children[rowIndex]
    if (!item) return
    Qt.callLater(function () {
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  SessionsService {
    id: sessions
    settings: root.settings
    pluginDir: root.pluginDir
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { sessions.refresh(); return "ok" }
    function label(): string { return root.indicatorStyle + " => " + root.barLabel() }
    // Jump to whatever needs a human: bindable to a key, same as a middle click.
    function next(): string {
      var target = sessions.blocked[0] || sessions.working[0] || sessions.sessions[0]
      if (!target) return "no sessions"
      root.focusSession(target)
      return target.name + " (" + target.state + ")"
    }
    // Focus one named session (bar name, herdr pane id, or pid).
    function focus(target: string): string {
      for (var i = 0; i < sessions.sessions.length; i++) {
        var s = sessions.sessions[i]
        if (s.name === target || String(s.paneId) === target || String(s.pid) === target) {
          root.focusSession(s)
          return s.name + " (" + s.state + ")"
        }
      }
      return "no session matching " + target
    }
    function status(): string {
      return sessions.count + " sessions · " + sessions.blocked.length + " blocked · "
        + sessions.working.length + " working · " + sessions.done.length + " done · "
        + sessions.idle.length + " idle"
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: sessions.refresh()
  }

  Timer {
    interval: 450
    running: root.animateWorking && root.visible && sessions.working.length > 0
    repeat: true
    onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % 4
  }

  // Focusing while the popup is still closing loses the race with the panel
  // handing focus back, so the dispatch waits for the close to land.
  property var pendingFocus: null

  Timer {
    id: focusDelay
    interval: 80
    onTriggered: {
      if (root.pendingFocus) sessions.focus(root.pendingFocus)
      root.pendingFocus = null
    }
  }

  function focusSession(entry) {
    if (!entry) return
    root.pendingFocus = entry
    root.close()
    focusDelay.restart()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Blocked count wins the label; otherwise the number of live sessions.
    text: root.barLabel()
    // The label paints its own colours, so leave the active tint to the styles
    // that draw a single uncoloured glyph.
    useActiveColor: root.indicatorStyle === "count"
    active: sessions.needsAttention
    dimmed: sessions.working.length === 0 && sessions.blocked.length === 0
    fontSize: Style.font.caption

    // A blocked agent breathes rather than blinks: visible in peripheral vision,
    // not a strobe next to the clock.
    SequentialAnimation on opacity {
      running: root.pulseBlocked && root.visible && sessions.blocked.length > 0
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
      onStopped: button.opacity = 1
    }
    tooltipText: {
      if (sessions.count === 0) return "No agent sessions running"
      var parts = []
      if (sessions.blocked.length > 0) parts.push(sessions.blocked.length + " blocked")
      if (sessions.working.length > 0) parts.push(sessions.working.length + " working")
      if (sessions.done.length > 0) parts.push(sessions.done.length + " done")
      if (sessions.idle.length > 0) parts.push(sessions.idle.length + " idle")
      return "Claude sessions: " + parts.join(" · ")
    }
    onPressed: function (b) {
      if (b === Qt.RightButton) sessions.refresh()
      else if (b === Qt.MiddleButton) {
        // Jump straight to whatever is asking for you, else the newest worker.
        var target = sessions.blocked[0] || sessions.working[0] || sessions.sessions[0]
        if (target) root.focusSession(target)
      } else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = t.toLowerCase()
        if (key === "r") sessions.refresh()
        else if (key === "c") {
          var entry = sessions.sessions[root.rowIndex]
          if (entry) sessions.copyText(entry.cwd)
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: sessions.count + (sessions.count === 1 ? " session" : " sessions")
            meta: sessions.blocked.length > 0
              ? sessions.blocked.length + " waiting on you"
              : sessions.working.length + " working"
            detail: sessions.done.length + " done · " + sessions.idle.length + " idle"
            foreground: sessions.needsAttention ? root.urgent : root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: sessions.needsAttention ? "󰀦" : "󰚩"
                color: sessions.needsAttention ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !sessions.loading
                onClicked: sessions.refresh()
              }
            }
          }

          Text {
            visible: sessions.lastError !== ""
            width: parent.width
            text: sessions.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: sessionColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: sessions.sessions
              SessionRow {
                required property var modelData
                required property int index
                width: sessionColumn.width
                entry: modelData
                rowNumber: index
              }
            }
          }
        }
      }
    }
  }

  component SessionRow: CursorSurface {
    id: sessionRow
    property var entry: null
    property int rowNumber: 0
    readonly property string state: entry ? String(entry.state || "idle") : "idle"
    readonly property string title: entry ? String(entry.title || "untitled") : ""
    readonly property string dir: entry ? String(entry.dir || "") : ""
    readonly property string name: entry ? String(entry.name || "") : ""
    readonly property string herdPane: entry && entry.paneId ? String(entry.paneId) : ""
    readonly property string agent: entry ? String(entry.agent || "agent") : ""
    readonly property int ageSec: entry ? (entry.ageSec || 0) : 0

    hasCursor: root.cursorActive && root.rowIndex === rowNumber
    current: state === "blocked"
    foreground: root.foreground

    implicitHeight: rowContent.implicitHeight + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      onEntered: { root.cursorActive = true; root.rowIndex = sessionRow.rowNumber }
      onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) sessions.copyText(sessionRow.entry.cwd)
        else root.focusSession(sessionRow.entry)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: root.stateGlyph(sessionRow.state)
        color: root.stateColor(sessionRow.state)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            text: root.agentGlyph(sessionRow.agent)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            Layout.fillWidth: true
            text: sessionRow.title
            color: sessionRow.state === "blocked" ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            Layout.fillWidth: true
            text: sessionRow.dir
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          // A herdr session lives in the multiplexer, not in a window, so say so:
          // clicking it attaches a terminal rather than raising one.
          Text {
            visible: sessionRow.herdPane !== ""
            text: "󰆍 herd " + sessionRow.herdPane
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      ColumnLayout {
        spacing: Style.space(1)
        Layout.alignment: Qt.AlignVCenter

        Text {
          Layout.alignment: Qt.AlignRight
          text: sessions.stateLabel(sessionRow.state)
          color: sessionRow.state === "blocked" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          Layout.alignment: Qt.AlignRight
          text: sessions.ageText(sessionRow.ageSec)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
