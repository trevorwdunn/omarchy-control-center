import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Control Center (plugin id trevor.hub): network, Bluetooth and volume
// behind one bar icon.
//
// Clicking the icon drops a small menu. Each row opens the real panel for
// that subject (the same Panel.qml the stand-alone bar widget uses) beside
// the menu, so nothing about those panels is reimplemented here.
//
// The panels are first-party code that expects the bar itself as `bar`. A
// third-party widget is only handed a restricted facade, so the hub borrows
// the real bar object from a first-party neighbour in the bar. If a future
// Omarchy closes that door the rows simply stop opening.
BarWidget {
  id: root
  moduleName: "trevor.hub"

  readonly property string home: Quickshell.env("HOME")
  readonly property string panelsDir: Quickshell.env("OMARCHY_PATH") + "/shell/plugins/panels"
  readonly property var sections: [
    { key: "network", label: "Network", icon: "󰖩",
      source: "file://" + home + "/.config/omarchy/plugins/trevor.network/Panel.qml",
      fallback: "file://" + panelsDir + "/network/Panel.qml", moduleName: "omarchy.network" },
    { key: "bluetooth", label: "Bluetooth", icon: "",
      source: "file://" + panelsDir + "/bluetooth/Panel.qml", fallback: "", moduleName: "omarchy.bluetooth" },
    { key: "audio", label: "Volume", icon: "",
      source: "file://" + panelsDir + "/audio/Panel.qml", fallback: "", moduleName: "omarchy.audio" }
  ]

  property bool menuOpen: false
  property string activeKey: ""
  property var realBar: null
  readonly property bool opened: menuOpen

  readonly property int menuWidth: Style.space(210)
  readonly property int panelWidth: Style.space(380)
  readonly property int gap: Style.space(8)
  readonly property int retreatDelayMs: Math.max(100, Number(setting("retreatDelayMs", 200)))

  implicitWidth: vertical ? barSize : button.implicitWidth
  implicitHeight: vertical ? button.implicitHeight : barSize

  function findSlot() {
    var o = root.parent
    for (var i = 0; i < 8 && o; i++) {
      if (o.entry !== undefined && o.region !== undefined && o.moduleName !== undefined) return o
      o = o.parent
    }
    return null
  }

  // The real bar, as held by any first-party widget in any section.
  function findRealBar() {
    var slot = findSlot()
    if (!slot || !slot.parent) return null
    var rows = [slot.parent]
    var up = slot.parent.parent
    for (var d = 0; d < 6 && up; d++) { rows.push(up); up = up.parent }
    var seen = []
    function walk(item, depth) {
      if (!item || depth > 7 || seen.length > 400) return null
      seen.push(item)
      if (item.entry !== undefined && item.activeItem && item.firstParty === true) {
        var b = item.activeItem.bar
        if (b && typeof b.requestPopout === "function" && b.barForeground !== undefined) return b
      }
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) {
        var found = walk(kids[i], depth + 1)
        if (found) return found
      }
      return null
    }
    for (var r = rows.length - 1; r >= 0; r--) {
      var hit = walk(rows[r], 0)
      if (hit) return hit
    }
    return null
  }

  function panelFor(key) {
    for (var i = 0; i < hosts.count; i++) {
      var h = hosts.itemAt(i)
      if (h && h.sectionKey === key) return h.item
    }
    return null
  }

  function hostFor(key) {
    for (var i = 0; i < hosts.count; i++) {
      var h = hosts.itemAt(i)
      if (h && h.sectionKey === key) return h
    }
    return null
  }

  // Window x where the menu card sits, mirroring PopupCard's own clamping.
  function menuLeft() {
    var win = root.QsWindow.window
    if (!win) return 0
    var centre = root.mapToItem(null, root.width / 2, 0).x
    return Math.max(gap, Math.min(centre - menuWidth / 2, win.width - menuWidth - gap))
  }

  // Put the (invisible) panel where its popup, which centres itself under
  // the panel's own button, lands beside the menu.
  function placeHost(host) {
    var win = root.QsWindow.window
    if (!win || !host) return
    var left = menuLeft()
    var x = left - gap - panelWidth
    if (x < gap) x = left + menuWidth + gap
    var centre = x + panelWidth / 2
    var local = root.mapFromItem(null, centre, 0)
    host.x = local.x - host.width / 2
  }

  function showSection(key) {
    if (!realBar) realBar = findRealBar()
    if (activeKey === key) return
    hideSection()
    var host = hostFor(key)
    if (!host) return
    host.active = true
    activeKey = key
    Qt.callLater(function() {
      if (root.activeKey !== key || !host.item) return
      root.placeHost(host)
      if (typeof host.item.open === "function") host.item.open()
    })
  }

  function hideSection() {
    var panel = panelFor(activeKey)
    activeKey = ""
    if (panel && panel.opened && typeof panel.close === "function") panel.close()
  }

  function open() { realBar = findRealBar(); menuOpen = true }
  function close() { hideSection(); menuOpen = false; sticky = false }

  // Opened from a keybinding the pointer may be nowhere near the bar, so the
  // menu stays until it is toggled or closed instead of timing out.
  property bool sticky: false
  property string pendingSection: ""

  function onFocusedMonitor() {
    var win = root.QsWindow.window
    var monitor = Hyprland.focusedMonitor
    return !!(win && win.screen && monitor && String(win.screen.name) === String(monitor.name))
  }
  function openHere() { if (onFocusedMonitor()) { sticky = true; open() } }
  function toggleHere() { if (!onFocusedMonitor()) return; if (menuOpen) close(); else openHere() }
  function showHere() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    var section = ""
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].pendingSection) section = items[i].pendingSection
    if (!onFocusedMonitor() || section === "") return
    openHere()
    showSection(section)
  }
  function toggle() { if (menuOpen) close(); else open() }

  IpcHandler {
    target: "trevor.hub"
    // A bar exists per monitor and only one instance owns this target, so
    // each call is relayed and answered by the bar on the focused monitor.
    function open(): void { root.broadcast("openHere") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggleHere") }
    function show(section: string): void { root.pendingSection = section; root.broadcast("showHere") }
    function status(): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      var out = []
      for (var i = 0; i < items.length; i++) {
        var w = items[i]
        if (!w) continue
        var win = w.QsWindow.window
        out.push({ screen: win && win.screen ? String(win.screen.name) : "", menuOpen: w.menuOpen, active: w.activeKey,
          sticky: w.sticky, pointerInside: w.pointerInside(), probe: w.activeKey !== "" && w.probeFor(w.activeKey) !== null })
      }
      return JSON.stringify(out)
    }
  }

  // The popup object inside a loaded panel. Stock panels use KeyboardPanel: a
  // full-screen overlay layer with the visible card placed inside it, so
  // while one is open the pointer is "in" that overlay wherever it goes and
  // the menu underneath sees no hover at all.
  function popupOf(panel) {
    if (!panel) return null
    var lists = [panel.data, panel.resources]
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l]
      if (!list) continue
      for (var i = 0; i < list.length; i++) {
        var o = list[i]
        if (o && o.anchorItem !== undefined && o.coordinatorKey !== undefined) return o
      }
    }
    return null
  }

  // The card item inside that overlay, and a hover probe on the overlay's
  // root that reports where the pointer is anywhere on the screen.
  property var probes: ({})

  function cardOf(popup) {
    var content = popup ? popup.contentItem : null
    if (!content || !content.length || !content[0] || !content[0].parent) return null
    return content[0].parent.parent || content[0].parent
  }

  function probeFor(key) {
    if (probes[key]) return probes[key]
    var card = cardOf(popupOf(panelFor(key)))
    if (!card) return null
    var top = card
    while (top.parent) top = top.parent
    var handler = Qt.createQmlObject("import QtQuick; HoverHandler {}", top, "hubProbe")
    probes[key] = { handler: handler, card: card, top: top }
    return probes[key]
  }

  // How far outside the menu and the side panel the pointer may wander
  // before the Control Center retreats.
  readonly property int retreatDistance: Math.max(0, Number(setting("retreatDistance", 56)))

  function near(px, py, x, y, w, h) {
    var m = retreatDistance
    return px >= x - m && px <= x + w + m && py >= y - m && py <= y + h + m
  }

  function pointerInside() {
    if (activeKey === "") return buttonHover.hovered || menu.containsMouse
    var probe = probeFor(activeKey)
    // No probe (a panel built some other way): stay open while it is.
    if (!probe || !probe.handler) return true
    if (!probe.handler.hovered) return buttonHover.hovered || menu.containsMouse
    var pos = probe.handler.point.position
    var c = probe.card.mapToItem(probe.top, 0, 0)
    if (near(pos.x, pos.y, c.x, c.y, probe.card.width, probe.card.height)) return true
    // The menu, plus the strip of bar above it, in the same screen space.
    var win = root.QsWindow.window
    var barH = win ? win.height : barSize
    return near(pos.x, pos.y, menuLeft(), 0, menuWidth, barH + gap + menu.implicitHeight)
  }

  // Retreat once the pointer has left the icon, the menu and the side panel
  // for a moment. Opened from a keybinding, it waits for the pointer to
  // arrive first. A side panel that closes by itself (click outside) takes
  // its highlight with it.
  Timer {
    interval: 120
    running: root.menuOpen
    repeat: true
    onTriggered: {
      var panel = root.panelFor(root.activeKey)
      if (root.activeKey !== "" && panel && !panel.opened && !openGrace.running) root.activeKey = ""
      if (root.pointerInside()) {
        root.sticky = false
        leaveTimer.stop()
      } else if (!root.sticky && !openGrace.running && !leaveTimer.running) {
        leaveTimer.start()
      }
    }
  }
  Timer { id: leaveTimer; interval: root.retreatDelayMs; onTriggered: if (!root.sticky && !root.pointerInside()) root.close() }
  // Panels report `opened` a beat after open() is called, and the pointer
  // needs a moment to cross the gap between the menu and a side panel.
  Timer { id: openGrace; interval: 600 }
  onActiveKeyChanged: if (activeKey !== "") openGrace.restart()

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    width: implicitWidth
    height: implicitHeight
    useActiveColor: false
    tooltipText: "Control Center"
    // Two stacked switches, one off and one on, drawn here rather than taken
    // from a font or an image so it stays crisp at any bar size and follows
    // the bar's text colour.
    iconComponent: Component {
      Item {
        id: glyph
        readonly property color ink: root.bar ? root.bar.barForeground : Color.foreground
        readonly property real u: width / 16

        // Narrower than the canvas so the pair reads as two switches, not two
        // bars: each track is a little over twice as wide as it is tall.
        readonly property real trackW: u * 12
        readonly property real trackH: u * 5.6
        readonly property real trackX: (width - trackW) / 2

        // Off: outlined track, solid knob on the left.
        Rectangle {
          x: glyph.trackX; y: glyph.u * 1.6
          width: glyph.trackW; height: glyph.trackH
          radius: height / 2
          color: "transparent"
          border.width: Math.max(1, glyph.u * 1.2)
          border.color: glyph.ink
          Rectangle {
            width: glyph.u * 2.2; height: width; radius: width / 2
            color: glyph.ink
            anchors.verticalCenter: parent.verticalCenter
            x: glyph.u * 1.9
          }
        }

        // On: solid track, knob punched out on the right.
        Rectangle {
          x: glyph.trackX; y: glyph.u * 8.8
          width: glyph.trackW; height: glyph.trackH
          radius: height / 2
          color: glyph.ink
          Rectangle {
            width: glyph.u * 3.0; height: width; radius: width / 2
            color: Color.background
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - width - glyph.u * 1.3
          }
        }
      }
    }
    onPressed: function(mouseButton) { root.toggle() }

    HoverHandler { id: buttonHover }
  }

  // The real panels, loaded on first use and kept invisible: only their
  // popups are ever seen.
  Repeater {
    id: hosts
    model: root.sections

    Loader {
      required property var modelData
      readonly property string sectionKey: modelData.key
      active: false
      source: modelData.source
      width: 1
      height: root.height
      opacity: 0
      enabled: false
      onStatusChanged: {
        if (status === Loader.Error && modelData.fallback !== "" && source != modelData.fallback) source = modelData.fallback
      }
      onLoaded: {
        if ("bar" in item) item.bar = root.realBar
        if ("moduleName" in item) item.moduleName = modelData.moduleName
        if ("settings" in item) item.settings = ({})
        // Two handlers for one IPC target would fight; the bar's own copy
        // (when it is in the layout) keeps it.
        if ("manageIpc" in item) item.manageIpc = false
      }
    }
  }

  HubCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: fittedContentWidth(root.menuWidth)
    contentHeight: fittedContentHeight(rows.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property string family: root.bar ? root.bar.fontFamily : Style.font.family

    Column {
      id: rows
      anchors.fill: parent
      spacing: Style.space(2)

      Repeater {
        model: root.sections

        Rectangle {
          id: row
          required property var modelData
          readonly property bool current: root.activeKey === modelData.key
          width: rows.width
          height: Style.space(34)
          radius: Style.space(6)
          color: current ? Util.alpha(Color.accent, 0.22)
            : (rowMouse.containsMouse ? Util.alpha(menu.fg, 0.10) : "transparent")

          Behavior on color { ColorAnimation { duration: 110 } }

          Text {
            id: chevron
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: menu.fg
            opacity: row.current ? 0.9 : 0.4
            font.family: menu.family
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.left: chevron.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label
            color: menu.fg
            font.family: menu.family
            font.pixelSize: Style.font.body
            font.weight: row.current ? Font.DemiBold : Font.Normal
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.icon
            color: menu.fg
            opacity: 0.85
            font.family: menu.family
            font.pixelSize: Style.font.body
          }

          Timer { id: dwell; interval: 160; onTriggered: if (rowMouse.containsMouse) root.showSection(row.modelData.key) }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: dwell.restart()
            onExited: dwell.stop()
            onClicked: root.showSection(row.modelData.key)
          }
        }
      }
    }
  }
}
