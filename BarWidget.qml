import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// Control Center (plugin id trevor.hub): the everyday switches and sliders
// behind one bar icon, laid out after the macOS Control Center.
//
// Clicking the icon drops a card of tiles: Wi-Fi, Bluetooth and LocalSend with
// what each is connected to, Do Not Disturb, Night Light and Stay Awake,
// display brightness, volume, and the batteries of up to five peripherals.
// The round buttons switch things on and off in place. The rest of a row
// opens the real panel for that subject (the same Panel.qml the stand-alone
// bar widget uses) beside the card, so nothing about those panels is
// reimplemented here.
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
      source: "file://" + panelsDir + "/audio/Panel.qml", fallback: "", moduleName: "omarchy.audio" },
    { key: "monitor", label: "Display", icon: "",
      source: "file://" + panelsDir + "/monitor/Panel.qml", fallback: "", moduleName: "omarchy.monitor" }
  ]

  property bool menuOpen: false
  property string activeKey: ""
  property var realBar: null
  readonly property bool opened: menuOpen

  readonly property int menuWidth: Style.space(372)
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

  function open() { realBar = findRealBar(); cursor = null; menuOpen = true }
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
          sticky: w.sticky, pointerInside: w.pointerInside(), cursor: w.cursor, iconX: w.mapToItem(null, 0, 0).x, menuLeft: w.menuLeft(), card: w.cardRect() })
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

  // The card item inside that overlay. The overlay spans the screen, so the
  // card's scene position is its position on the screen.
  function cardOf(popup) {
    var content = popup ? popup.contentItem : null
    if (!content || !content.length || !content[0] || !content[0].parent) return null
    return content[0].parent.parent || content[0].parent
  }

  // How far outside the menu and the side panel the pointer may wander
  // before the Control Center retreats.
  readonly property int retreatDistance: Math.max(0, Number(setting("retreatDistance", 56)))

  function near(px, py, x, y, w, h) {
    var m = retreatDistance
    return px >= x - m && px <= x + w + m && py >= y - m && py <= y + h + m
  }

  // Where the pointer is, in this bar window's coordinates, asked of
  // Hyprland while the menu is open. Hover alone cannot say: it only reports
  // the pointer while it is exactly over the icon or a card, goes quiet in
  // the gap between them, and goes stale under a panel's full-screen overlay.
  property var cursor: null

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = /(-?\d+)\s*,\s*(-?\d+)/.exec(text)
        var win = root.QsWindow.window
        var monitor = win && win.screen ? Hyprland.monitorFor(win.screen) : null
        root.cursor = m && monitor ? { x: Number(m[1]) - monitor.x, y: Number(m[2]) - monitor.y } : null
        root.checkPointer()
      }
    }
  }

  // Inside means on or near the icon, the menu (with the strip of bar above
  // it), or the open side panel.
  function pointerInside() {
    var win = root.QsWindow.window
    if (!cursor || !win) return buttonHover.hovered || menu.containsMouse || activeKey !== ""
    var px = cursor.x, py = cursor.y
    var barH = win.height
    var icon = root.mapToItem(null, 0, 0)
    if (near(px, py, icon.x, 0, root.width, barH)) return true
    if (near(px, py, menuLeft(), 0, menuWidth, barH + gap + menu.implicitHeight)) return true
    if (activeKey === "") return false
    var card = cardOf(popupOf(panelFor(activeKey)))
    // No card (a panel built some other way): stay open while it is.
    if (!card) return true
    var c = card.mapToItem(null, 0, 0)
    return near(px, py, c.x, c.y, card.width, card.height)
  }

  function cardRect() {
    var card = activeKey !== "" ? cardOf(popupOf(panelFor(activeKey))) : null
    if (!card) return null
    var c = card.mapToItem(null, 0, 0)
    return { x: c.x, y: c.y, w: card.width, h: card.height }
  }

  function checkPointer() {
    if (!menuOpen) return
    var panel = panelFor(activeKey)
    if (activeKey !== "" && panel && !panel.opened && !openGrace.running) activeKey = ""
    if (pointerInside()) {
      sticky = false
      leaveTimer.stop()
    } else if (!sticky && !openGrace.running && !leaveTimer.running) {
      leaveTimer.start()
    }
  }

  // Retreat once the pointer has left the icon, the menu and the side panel
  // for a moment. Opened from a keybinding, it waits for the pointer to
  // arrive first. A side panel that closes by itself (click outside) takes
  // its highlight with it.
  Timer {
    interval: 120
    running: root.menuOpen
    repeat: true
    onTriggered: if (!cursorProc.running) cursorProc.running = true
  }
  Timer { id: leaveTimer; interval: root.retreatDelayMs; onTriggered: if (!root.sticky && !root.pointerInside()) root.close() }
  // Panels report `opened` a beat after open() is called, and the pointer
  // needs a moment to cross the gap between the menu and a side panel.
  Timer { id: openGrace; interval: 600 }
  onActiveKeyChanged: if (activeKey !== "") openGrace.restart()

  // ------------------------------------------------------------ tile state
  //
  // Network, Bluetooth, volume and UPower batteries are live bindings. The
  // rest (Do Not Disturb, Night Light, Stay Awake, brightness, AirDrop and
  // the batteries UPower does not know about) is read by status.sh while the
  // card is open.

  function glyph(codePoint) { return String.fromCodePoint(codePoint) }

  readonly property string screenName: {
    var win = root.QsWindow.window
    return win && win.screen ? String(win.screen.name) : ""
  }

  function netDevice(type) {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  readonly property var wifiDevice: netDevice(DeviceType.Wifi)
  readonly property var wiredDevice: netDevice(DeviceType.Wired)
  readonly property var wifiNetwork: {
    var networks = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }
  readonly property bool wifiOn: Networking.wifiEnabled
  readonly property bool wiredUp: !!(wiredDevice && wiredDevice.connected)
  readonly property string networkStatus: {
    var ssid = wifiNetwork ? String(wifiNetwork.name || "") : ""
    if (wiredUp) return ssid !== "" ? ssid + " + Ethernet" : "Ethernet"
    if (ssid !== "") return ssid
    return wifiOn ? "Not connected" : "Off"
  }

  function toggleWifi() {
    if (Networking.backend !== NetworkBackendType.NetworkManager) return
    Networking.wifiEnabled = !Networking.wifiEnabled
  }

  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!(btAdapter && btAdapter.enabled)
  readonly property var btConnected: {
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    var out = []
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].connected) out.push(devices[i])
    return out
  }
  readonly property string bluetoothStatus: {
    if (!btAdapter) return "Not available"
    if (!btOn) return "Off"
    if (btConnected.length === 0) return "On"
    if (btConnected.length === 1) return String(btConnected[0].name || "1 device")
    return btConnected.length + " devices"
  }

  // The rfkill helper rather than adapter.enabled, as the Bluetooth panel
  // does, so the choice survives a reboot.
  function toggleBluetooth() {
    if (btAdapter) Quickshell.execDetached(["omarchy-bluetooth-power", btOn ? "off" : "on"])
  }

  // Volume belongs to the sink the output really uses, which is not the
  // default sink while a speaker tuning fronts it; status.sh names it.
  readonly property var sink: Pipewire.defaultAudioSink
  property string volumeSinkName: ""
  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink || volumeSinkName === String(sink.name)) return sink
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio) return n
    }
    return sink
  }
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property real volume: hasOutput ? volumeSink.audio.volume : 0
  readonly property bool muted: hasOutput ? volumeSink.audio.muted : false
  readonly property string outputName: sink ? String(sink.description || sink.nickname || sink.name || "") : "No output"

  PwObjectTracker { objects: [root.sink, root.volumeSink].filter(function(n) { return !!n }) }

  function setVolume(value) {
    if (!hasOutput) return
    volumeSink.audio.volume = Math.max(0, Math.min(1, value))
    if (value > 0 && volumeSink.audio.muted) volumeSink.audio.muted = false
  }
  function toggleMute() { if (hasOutput) volumeSink.audio.muted = !volumeSink.audio.muted }

  property bool dnd: false
  property bool nightLight: false
  property bool stayAwake: false
  property bool airdropKnown: false
  property bool airdropOn: false
  property string airdropStatus: ""
  // AirDrop (omdrop) is off the card until it works on this machine.
  readonly property bool airdropShown: airdropKnown && setting("showAirdrop", false) === true
  property bool localsendKnown: false
  property bool localsendOn: false
  property int brightness: -1
  property var headsetReport: null
  property var podsReport: null
  property var extraBatteries: []

  // A switch shows the new state the moment it is clicked; readings taken
  // before the change has landed are ignored for that key.
  property var holds: ({})
  function hold(key) { holds[key] = Date.now() + 2500; refreshSoon.restart() }
  function held(key) { return (holds[key] || 0) > Date.now() }

  function parseJson(text) {
    try { return JSON.parse(text) } catch (e) { return null }
  }

  function applyStatus(text) {
    var seen = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var cut = lines[i].indexOf("=")
      if (cut > 0) seen[lines[i].slice(0, cut)] = lines[i].slice(cut + 1)
    }
    if (!held("dnd") && seen.dnd) dnd = seen.dnd === "on"
    var night = parseJson(seen.night)
    if (!held("night") && night) nightLight = night.enabled === true
    var idle = parseJson(seen.idle)
    if (!held("idle") && idle) stayAwake = idle.stayAwake === true
    var level = parseInt(seen.brightness, 10)
    if (!held("brightness") && !brightnessSlider.dragging) brightness = isNaN(level) ? -1 : Math.max(0, Math.min(100, level))
    var drop = String(seen.airdrop || "")
    airdropKnown = drop !== "" && drop !== "Not available"
    if (!held("airdrop")) {
      airdropOn = airdropKnown && !/off$/i.test(drop)
      airdropStatus = /^omdrop /i.test(drop) ? (airdropOn ? "On" : "Off") : drop
    }
    var send = String(seen.localsend || "")
    localsendKnown = send === "on" || send === "off"
    if (!held("localsend") && localsendKnown) localsendOn = send === "on"
    volumeSinkName = String(seen.sink || "")
    headsetReport = parseJson(seen.headset)
    podsReport = parseJson(seen.pods)
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
    if (!batteryProc.running) batteryProc.running = true
  }

  function toggleDnd() {
    dnd = !dnd
    hold("dnd")
    Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", dnd ? "on" : "off"])
  }
  function toggleNightLight() {
    nightLight = !nightLight
    hold("night")
    Quickshell.execDetached(["omarchy-toggle-nightlight"])
  }
  function toggleStayAwake() {
    stayAwake = !stayAwake
    hold("idle")
    Quickshell.execDetached(["omarchy-toggle-idle", stayAwake ? "stay-awake" : "allow-idle"])
  }
  function toggleAirdrop() {
    airdropOn = !airdropOn
    airdropStatus = airdropOn ? "Turning on" : "Turning off"
    hold("airdrop")
    Quickshell.execDetached(["omarchy-shell", "netmojo.omdrop", "toggle"])
  }

  function toggleLocalsend() {
    localsendOn = !localsendOn
    hold("localsend")
    Quickshell.execDetached(["omarchy-shell", "bredda.localsend", "receiver", localsendOn ? "on" : "off"])
  }
  // LocalSend's own panel drops from its bar icon, so the card steps aside.
  // Its IPC target belongs to one bar only, wherever that is, so the
  // LocalSend widget on this card's own bar is asked directly.
  function openLocalsend() {
    var name = screenName
    var host = realBar || findRealBar()
    var items = host && typeof host.moduleWidgets === "function" ? host.moduleWidgets("bredda.localsend") : []
    var target = null
    for (var i = 0; i < items.length; i++) {
      var win = items[i] ? items[i].QsWindow.window : null
      if (win && win.screen && String(win.screen.name) === name) target = items[i]
    }
    close()
    if (target && typeof target.open === "function") target.open()
    else Quickshell.execDetached(["omarchy-shell", "bredda.localsend", "open"])
  }

  // One write at a time: the newest value waits for the one in flight.
  property int brightnessWanted: -1
  function setBrightness(percent) {
    brightness = Math.max(1, Math.min(100, Math.round(percent)))
    brightnessWanted = brightness
    hold("brightness")
    if (brightnessProc.running) return
    brightnessWanted = -1
    brightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", screenName, brightness + "%"]
    brightnessProc.running = true
  }

  Process {
    id: statusProc
    command: ["bash", Qt.resolvedUrl("status.sh").toString().replace(/^file:\/\//, ""), root.screenName]
    stdout: StdioCollector { onStreamFinished: root.applyStatus(text) }
  }
  // Apart from status.sh: a receiver whose mouse is asleep takes a moment to
  // give up, and the switches should not wait for it.
  Process {
    id: batteryProc
    command: ["python3", Qt.resolvedUrl("batteries.py").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parseJson(text)
        root.extraBatteries = Array.isArray(parsed) ? parsed : []
      }
    }
  }
  Process {
    id: brightnessProc
    onRunningChanged: if (!running && root.brightnessWanted >= 0) root.setBrightness(root.brightnessWanted)
  }
  Timer { interval: 3000; running: root.menuOpen; repeat: true; triggeredOnStart: true; onTriggered: root.refreshStatus() }
  Timer { id: refreshSoon; interval: 2600; onTriggered: root.refreshStatus() }

  // Batteries, from four places: AirPods through librepods, Keychron mice and
  // Logitech Bolt devices through batteries.py, headsets through
  // headsetcontrol, and everything
  // UPower sees that is not this computer's own power (which covers
  // Bluetooth and most receivers).
  readonly property int batteryLimit: 5

  function batteryIcon(kind) {
    if (kind === "keyboard") return glyph(0xF030C)
    if (kind === "mouse") return glyph(0xF037D)
    if (kind === "headset") return glyph(0xF02CE)
    if (kind === "headphones") return glyph(0xF02CB)
    if (kind === "gamepad") return glyph(0xF02B4)
    if (kind === "phone") return glyph(0xF011C)
    return glyph(0xF0079)
  }

  function upowerKind(device) {
    var t = device.type
    if (t === UPowerDeviceType.Keyboard) return "keyboard"
    if (t === UPowerDeviceType.Mouse) return "mouse"
    if (t === UPowerDeviceType.Headset) return "headset"
    if (t === UPowerDeviceType.Headphones) return "headphones"
    if (t === UPowerDeviceType.GamingInput) return "gamepad"
    if (t === UPowerDeviceType.Phone) return "phone"
    return "other"
  }

  readonly property var batteries: {
    var out = []
    function known(name) {
      var n = String(name).toLowerCase()
      for (var i = 0; i < out.length; i++) {
        var o = out[i].name.toLowerCase()
        if (n !== "" && (o.indexOf(n) >= 0 || n.indexOf(o) >= 0)) return true
      }
      return false
    }

    var pods = podsReport
    if (pods && typeof pods === "object") {
      var parts = [["L", pods.left], ["R", pods.right], ["Case", pods["case"]], ["", pods.headset]]
      var levels = [], notes = [], charging = false
      for (var p = 0; p < parts.length; p++) {
        var part = parts[p][1]
        if (!part || part.available !== true || !(part.level >= 0)) continue
        if (parts[p][0] !== "Case") { levels.push(part.level); charging = charging || part.charging === true }
        if (parts[p][0] !== "") notes.push(parts[p][0] + " " + part.level + "%")
      }
      if (levels.length > 0) {
        out.push({ name: String(pods.device_name || pods.model_name || "AirPods"), kind: "headphones",
          percent: Math.min.apply(null, levels), charging: charging, note: notes.join("  ") })
      }
    }

    for (var k = 0; k < extraBatteries.length; k++) {
      var kc = extraBatteries[k]
      if (!kc || !(kc.percent >= 0)) continue
      out.push({ name: String(kc.name || "Device"), kind: String(kc.kind || "other"),
        percent: Math.round(kc.percent), charging: kc.charging === true, note: "" })
    }

    var headsets = headsetReport && headsetReport.devices ? headsetReport.devices : []
    for (var h = 0; h < headsets.length; h++) {
      var hs = headsets[h]
      var b = hs ? hs.battery : null
      if (!b || !(b.level >= 0) || b.status === "BATTERY_UNAVAILABLE") continue
      out.push({ name: String(hs.device || hs.product || "Headset"), kind: "headset",
        percent: Math.round(b.level), charging: b.status === "BATTERY_CHARGING", note: "" })
    }

    var devices = UPower.devices ? UPower.devices.values : []
    for (var u = 0; u < devices.length; u++) {
      var d = devices[u]
      if (!d || !d.isPresent || d.powerSupply || d.type === UPowerDeviceType.LinePower) continue
      var label = String(d.model || "")
      if (known(label)) continue
      var kind = upowerKind(d)
      if (label === "") label = kind === "other" ? "Device" : kind.charAt(0).toUpperCase() + kind.slice(1)
      out.push({ name: label, kind: kind, percent: Math.round(Number(d.percentage) * 100),
        charging: d.state === UPowerDeviceState.Charging, note: "" })
    }

    // More than fit: keep the ones closest to needing a charge.
    if (out.length > batteryLimit) {
      out.sort(function(a, b) { return a.percent - b.percent })
      out = out.slice(0, batteryLimit)
    }
    return out
  }

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
    contentHeight: fittedContentHeight(tiles.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property string family: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property int pad: Style.space(10)
    readonly property int rowHeight: Style.space(44)
    readonly property int topHeight: rowHeight * 3 + Style.space(8)

    Column {
      id: tiles
      anchors.fill: parent
      spacing: root.gap

      // Connectivity on the left; Do Not Disturb over two small switches on
      // the right.
      Row {
        width: tiles.width
        height: menu.topHeight
        spacing: root.gap

        Tile {
          id: connectivity
          width: Math.round((tiles.width - root.gap) * 0.56)
          height: parent.height
          fg: menu.fg

          Column {
            id: connRows
            anchors.fill: parent
            anchors.margins: Style.space(4)
            readonly property int count: 2 + (root.localsendKnown ? 1 : 0) + (root.airdropShown ? 1 : 0)
            readonly property int rowHeight: Math.floor(height / count)

            ConnRow {
              width: connRows.width
              height: connRows.rowHeight
              title: "Wi-Fi"
              status: root.networkStatus
              glyph: root.glyph(root.wifiOn ? 0xF05A9 : 0xF05AA)
              on: root.wifiOn
              current: root.activeKey === "network"
              fg: menu.fg
              family: menu.family
              onToggled: root.toggleWifi()
              onOpened: root.showSection("network")
            }
            ConnRow {
              width: connRows.width
              height: connRows.rowHeight
              title: "Bluetooth"
              status: root.bluetoothStatus
              glyph: root.glyph(root.btOn ? 0xF00AF : 0xF00B2)
              on: root.btOn
              current: root.activeKey === "bluetooth"
              fg: menu.fg
              family: menu.family
              onToggled: root.toggleBluetooth()
              onOpened: root.showSection("bluetooth")
            }
            ConnRow {
              visible: root.localsendKnown
              width: connRows.width
              height: connRows.rowHeight
              title: "LocalSend"
              status: root.localsendOn ? "Receiving" : "Off"
              glyph: root.glyph(0xF048A)
              icon: "file://" + root.home + "/.config/omarchy/plugins/bredda.localsend/assets/localsend-symbolic.svg"
              on: root.localsendOn
              fg: menu.fg
              family: menu.family
              onToggled: root.toggleLocalsend()
              onOpened: root.openLocalsend()
            }
            ConnRow {
              visible: root.airdropShown
              width: connRows.width
              height: connRows.rowHeight
              title: "AirDrop"
              status: root.airdropStatus
              glyph: root.glyph(0xF0003)
              on: root.airdropOn
              chevron: false
              fg: menu.fg
              family: menu.family
              onToggled: root.toggleAirdrop()
              onOpened: root.toggleAirdrop()
            }
          }
        }

        Column {
          width: tiles.width - root.gap - connectivity.width
          height: parent.height
          spacing: root.gap

          Tile {
            id: dndTile
            width: parent.width
            height: Math.floor((parent.height - root.gap) / 2)
            fg: menu.fg
            hot: dndMouse.containsMouse

            MouseArea {
              id: dndMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleDnd()
            }
            RoundToggle {
              id: dndDisc
              anchors.left: parent.left
              anchors.leftMargin: menu.pad
              anchors.verticalCenter: parent.verticalCenter
              on: root.dnd
              glyph: root.glyph(0xF0594)
              fg: menu.fg
              family: menu.family
              interactive: false
            }
            Text {
              anchors.left: dndDisc.right
              anchors.leftMargin: Style.space(9)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Do Not\nDisturb"
              color: menu.fg
              font.family: menu.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
          }

          Row {
            width: parent.width
            height: parent.height - root.gap - dndTile.height
            spacing: root.gap

            Repeater {
              model: [
                { key: "night", label: "Night\nLight", code: 0xF06E8 },
                { key: "awake", label: "Stay\nAwake", code: 0xF0176 }
              ]

              Tile {
                id: small
                required property var modelData
                readonly property bool on: modelData.key === "night" ? root.nightLight : root.stayAwake
                width: Math.floor((parent.width - root.gap) / 2)
                height: parent.height
                fg: menu.fg
                hot: smallMouse.containsMouse

                MouseArea {
                  id: smallMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: small.modelData.key === "night" ? root.toggleNightLight() : root.toggleStayAwake()
                }
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(3)

                  RoundToggle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Style.space(24)
                    on: small.on
                    glyph: root.glyph(small.modelData.code)
                    fg: menu.fg
                    family: menu.family
                    interactive: false
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: small.modelData.label
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.9
                    color: menu.fg
                    font.family: menu.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }

      // Display brightness of the monitor this card is on.
      Tile {
        id: displayTile
        visible: root.brightness >= 0
        width: tiles.width
        height: displayBody.implicitHeight + menu.pad * 2
        fg: menu.fg
        current: root.activeKey === "monitor"

        Column {
          id: displayBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: menu.pad
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: displayTitle.implicitHeight

            Text {
              id: displayTitle
              text: "Display"
              color: menu.fg
              font.family: menu.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
            Text {
              anchors.right: parent.right
              text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightness) + "%  " + root.glyph(0xF0142)
              color: menu.fg
              opacity: displayHead.containsMouse ? 0.95 : 0.6
              font.family: menu.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: displayHead
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSection("monitor")
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: sunIcon
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyph(0xF00E0)
              color: menu.fg
              font.family: menu.family
              font.pixelSize: Style.font.icon
            }
            PanelSlider {
              id: brightnessSlider
              width: parent.width - sunIcon.width - parent.spacing
              bar: root.bar
              minimum: 1
              maximum: 100
              step: 5
              integer: true
              value: Math.max(1, root.brightness)
              onMoved: function(v) { root.setBrightness(v) }
            }
          }
        }
      }

      // Output volume; the speaker mutes, the title opens the audio panel.
      Tile {
        width: tiles.width
        height: soundBody.implicitHeight + menu.pad * 2
        fg: menu.fg
        current: root.activeKey === "audio"

        Column {
          id: soundBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: menu.pad
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: soundTitle.implicitHeight

            Text {
              id: soundTitle
              text: "Sound"
              color: menu.fg
              font.family: menu.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
            Text {
              anchors.left: soundTitle.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: root.outputName + "  " + root.glyph(0xF0142)
              color: menu.fg
              opacity: soundHead.containsMouse ? 0.95 : 0.6
              font.family: menu.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: soundHead
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showSection("audio")
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: speakerIcon
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyph(root.muted || !root.hasOutput ? 0xF0581 : (root.volume < 0.34 ? 0xF057F : (root.volume < 0.67 ? 0xF0580 : 0xF057E)))
              color: root.muted ? Color.urgent : menu.fg
              font.family: menu.family
              font.pixelSize: Style.font.icon

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(5)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMute()
              }
            }
            PanelSlider {
              id: volumeSlider
              width: parent.width - speakerIcon.width - parent.spacing
              bar: root.bar
              enabled: root.hasOutput
              opacity: root.muted || !root.hasOutput ? 0.45 : 1.0
              value: root.volume
              onMoved: function(v) { root.setVolume(v) }
              onRightClicked: root.toggleMute()
            }
          }
        }
      }

      // Peripheral batteries, at most batteryLimit of them.
      Tile {
        width: tiles.width
        height: batteryBody.implicitHeight + menu.pad * 2
        fg: menu.fg

        Column {
          id: batteryBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: menu.pad
          spacing: Style.space(6)

          Text {
            text: "Batteries"
            color: menu.fg
            font.family: menu.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }

          Text {
            visible: root.batteries.length === 0
            text: "No peripherals are reporting a battery"
            color: menu.fg
            opacity: 0.6
            font.family: menu.family
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.batteries

            Item {
              id: cell
              required property var modelData
              readonly property bool low: !modelData.charging && modelData.percent <= 20
              readonly property color ink: low ? Color.urgent : menu.fg
              width: batteryBody.width
              height: Style.space(26)

              Text {
                id: cellIcon
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                text: root.batteryIcon(cell.modelData.kind)
                color: menu.fg
                font.family: menu.family
                font.pixelSize: Style.font.icon
              }
              Column {
                anchors.left: cellIcon.right
                anchors.leftMargin: Style.space(6)
                anchors.right: cellLevel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: cell.modelData.name
                  elide: Text.ElideRight
                  color: menu.fg
                  font.family: menu.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  visible: cell.modelData.note !== ""
                  width: parent.width
                  text: cell.modelData.note
                  elide: Text.ElideRight
                  color: menu.fg
                  opacity: 0.6
                  font.family: menu.family
                  font.pixelSize: Style.font.caption
                }
              }
              Text {
                id: cellLevel
                anchors.right: gauge.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: (cell.modelData.charging ? root.glyph(0xF0E7) + " " : "") + cell.modelData.percent + "%"
                color: cell.ink
                font.family: menu.family
                font.pixelSize: Style.font.bodySmall
              }
              // A small battery, drawn so it stays crisp at any scale.
              Item {
                id: gauge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(27)
                height: Style.space(12)

                Rectangle {
                  id: shell
                  width: parent.width - Style.space(3)
                  height: parent.height
                  radius: Style.cornerRadius > 0 ? Style.space(3) : 0
                  color: "transparent"
                  border.width: 1
                  border.color: Util.alpha(menu.fg, 0.55)

                  Rectangle {
                    x: Style.space(2)
                    y: Style.space(2)
                    height: parent.height - Style.space(4)
                    width: Math.max(Style.space(2), (parent.width - Style.space(4)) * Math.max(0, Math.min(100, cell.modelData.percent)) / 100)
                    radius: Style.cornerRadius > 0 ? Style.space(1) : 0
                    color: cell.ink
                  }
                }
                Rectangle {
                  anchors.left: shell.right
                  anchors.leftMargin: 1
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(2)
                  height: Style.space(5)
                  radius: 1
                  color: Util.alpha(menu.fg, 0.55)
                }
              }
            }
          }
        }
      }
    }
  }
}
