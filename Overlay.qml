import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ColorUtils.js" as CU

// The studio: current-color hero with format chips and WCAG contrast,
// an SV-square + hue-bar chooser, harmony rows, pinned colors, pick
// history, and the active Omarchy theme palette. History/pin/theme swatches
// SELECT (become the working color, remembered across opens); the hero code,
// hero swatch, and harmony palette colors COPY in the active format; the
// format chips switch that format.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  // Current color as HSV — single source of truth; hex is derived.
  property real hue: 215
  property real sat: 0.33
  property real val: 0.95
  readonly property string currentHex: CU.toHex(CU.hsvToRgb({ h: hue, s: sat, v: val }))
  readonly property var currentRgb: CU.parseHex(currentHex)

  // Shared state lives in the service (sole writer of state.json); the
  // overlay reads it reactively and mutates through service calls.
  readonly property var history: service ? service.history : []
  readonly property var pinned: service ? service.pinned : []
  readonly property string defaultFormat: service ? service.defaultFormat : "hex"
  readonly property var savedHarmonies: service ? service.savedHarmonies : []
  readonly property var imagePalette: service ? service.imagePalette : null
  property string copiedFlash: ""
  property bool editingHex: false
  property var themeColors: []
  property string hoverLabel: ""

  // Adobe-style harmony state: which chooser is shown and which rule drives
  // the 5-slot palette. The palette recomputes from the base HSV live.
  readonly property string chooserMode: service ? service.chooserMode : "wheel"
  property string harmonyRule: "complementary"
  readonly property var paletteColors: CU.palette(harmonyRule, { h: hue, s: sat, v: val })

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(780), panel.height - Style.gapsOut * 2)
  property int swatchSize: Style.space(26)

  function open(payloadJson) {
    root.opened = true
    if (root.service && CU.parseHex(root.service.currentColor)) root.setCurrent(root.service.currentColor)
    else if (root.history.length > 0) root.setCurrent(root.history[0].hex)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    if (root.service) root.service.setCurrentColor(root.currentHex)
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.alexdont.color-studio")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setCurrent(hex) {
    var rgb = CU.parseHex(hex)
    if (!rgb) return
    var hsv = CU.rgbToHsv(rgb)
    // Preserve hue when the new color is grey/white/black so the chooser
    // does not snap to red (hue 0) on desaturated colors.
    if (hsv.s > 0.001 && hsv.v > 0.001) root.hue = hsv.h
    root.sat = hsv.s
    root.val = hsv.v
  }

  function addToHistory(hex, src) {
    if (root.service) root.service.addHistory(hex, src)
  }

  // Select: load a color as the working color and persist it, so the popup
  // reopens on it. History/pin clicks select quietly; theme clicks also log.
  function selectSwatch(hex) {
    root.setCurrent(hex)
    if (root.service) root.service.setCurrentColor(hex)
  }

  function chooseSwatch(hex) {
    root.selectSwatch(hex)
    root.addToHistory(CU.toHex(CU.parseHex(hex)), "studio")
  }

  // Copy any color in the active display format; the code shown IS what
  // lands on the clipboard. Only the working color is logged to history —
  // harmony copies pass record=false so grabbing five palette colors never
  // resets or reshuffles anything.
  function copyColor(hex, record) {
    var rgb = CU.parseHex(hex)
    if (!rgb) return
    Quickshell.execDetached(["wl-copy", CU.format(rgb, root.defaultFormat)])
    if (record) root.addToHistory(CU.toHex(rgb), "studio")
    root.copiedFlash = CU.toHex(rgb)
    copiedReset.restart()
  }

  function fmtOf(hex) {
    var rgb = CU.parseHex(hex)
    return rgb ? CU.format(rgb, root.defaultFormat) : ""
  }

  function removeFromHistory(index) {
    if (root.service) root.service.removeHistory(index)
  }

  function togglePin() {
    if (root.service) root.service.togglePin(root.currentHex)
  }

  function setMode(fmt) {
    if (root.service) root.service.setDefaultFormat(fmt)
  }

  function loadThemeColors(raw) {
    var out = [], seen = {}
    var lines = raw.split("\n")
    for (var j = 0; j < lines.length; j++) {
      var parts = lines[j].split("\t")
      if (parts.length < 2) continue
      var rgb = CU.parseHex(parts[1].trim())
      if (!rgb) continue
      var hex = CU.toHex(rgb)
      if (seen[hex]) continue
      seen[hex] = true
      out.push({ name: parts[0].trim(), hex: hex })
      if (out.length >= 16) break
    }
    root.themeColors = out
  }

  Timer { id: copiedReset; interval: 1200; onTriggered: root.copiedFlash = "" }

  // Follow screen picks live: when the service's working color changes while
  // the studio is open (e.g. an eyedropper pick), jump the wheel to it.
  Connections {
    target: root.service
    function onImagePaletteChanged() {
      if (root.service.imagePalette) root.service.setChooserMode("image")
    }
    function onCurrentColorChanged() {
      if (root.opened && CU.parseHex(root.service.currentColor)) root.setCurrent(root.service.currentColor)
    }
  }

  Process {
    id: themeProbe
    command: ["sh", "-c", "omarchy-theme-color --all 2>/dev/null || true"]
    running: true
    stdout: StdioCollector { onStreamFinished: root.loadThemeColors(text) }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "io-github-alexdont-color-studio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Drop an image anywhere on the studio to pull its palette.
      DropArea {
        id: imageDrop
        anchors.fill: parent
        onDropped: function(drop) {
          if (!root.service) return
          var path = ""
          if (drop.hasUrls && drop.urls.length > 0) path = String(drop.urls[0])
          else if (drop.hasText) path = String(drop.text).trim().split("\n")[0]
          path = decodeURIComponent(path.replace(/^file:\/\//, ""))
          if (path) root.service.extractFromImage(path)
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        visible: imageDrop.containsDrag
        color: "transparent"
        border.width: Style.space(3)
        border.color: root.selectedText
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.dismiss()

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.md

          // ---- Hero: current color, hex field, format chips, contrast ----
          Row {
            width: parent.width
            spacing: Style.spacing.md

            Rectangle {
              id: heroSwatch
              width: Style.space(72)
              height: Style.space(72)
              radius: root.cornerRadius
              color: root.currentHex
              border.width: 1
              border.color: root.border

              // The big swatch is a copy target too — easier to hit than
              // the code text. The pin badge sits on top and wins its area.
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyColor(root.currentHex, true)
              }

              Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                width: Style.space(20)
                height: Style.space(20)
                radius: width / 2
                color: pinHover.containsMouse ? root.selectedBackground : root.background
                opacity: 0.9

                Text {
                  anchors.centerIn: parent
                  text: root.pinned.indexOf(root.currentHex) >= 0 ? "󰐄" : "󰐃"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                MouseArea {
                  id: pinHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.togglePin()
                }
              }
            }

            Column {
              width: parent.width - heroSwatch.width - Style.spacing.md
              spacing: Style.space(6)

              Row {
                spacing: Style.spacing.md

                // The working color's code in the active format — click it
                // to copy. The pencil flips the field into hex entry.
                Rectangle {
                  width: (root.editingHex ? hexInput.implicitWidth : codeText.implicitWidth) + Style.spacing.md * 2
                  height: Style.space(30)
                  radius: root.cornerRadius / 2
                  color: root.selectedBackground
                  opacity: (root.editingHex || codeHover.containsMouse) ? 1 : 0.75

                  Text {
                    id: codeText
                    visible: !root.editingHex
                    anchors.centerIn: parent
                    text: root.copiedFlash === root.currentHex ? "copied ✓" : root.fmtOf(root.currentHex)
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  MouseArea {
                    id: codeHover
                    visible: !root.editingHex
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyColor(root.currentHex, true)
                  }

                  TextInput {
                    id: hexInput
                    visible: root.editingHex
                    anchors.centerIn: parent
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    selectByMouse: true
                    onAccepted: { root.setCurrent(text); root.editingHex = false; keyCatcher.forceActiveFocus() }
                    Keys.onEscapePressed: { root.editingHex = false; keyCatcher.forceActiveFocus() }
                  }
                }

                Rectangle {
                  width: Style.space(26)
                  height: Style.space(30)
                  radius: root.cornerRadius / 2
                  color: (editHover.containsMouse || root.editingHex) ? root.selectedBackground : "transparent"
                  border.width: 1
                  border.color: root.border

                  Text {
                    anchors.centerIn: parent
                    text: "󰏫"
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    id: editHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.editingHex = !root.editingHex
                      if (root.editingHex) { hexInput.text = root.currentHex; hexInput.forceActiveFocus(); hexInput.selectAll() }
                      else keyCatcher.forceActiveFocus()
                    }
                  }
                }

                // WCAG contrast vs white and black at the AA threshold.
                Repeater {
                  model: [{ bg: "#ffffff", label: "on white" }, { bg: "#000000", label: "on black" }]

                  Rectangle {
                    required property var modelData
                    readonly property real ratio: CU.contrastRatio(root.currentRgb, CU.parseHex(modelData.bg))
                    width: contrastText.implicitWidth + Style.spacing.md * 2
                    height: Style.space(30)
                    radius: root.cornerRadius / 2
                    color: modelData.bg
                    border.width: 1
                    border.color: root.border

                    Text {
                      id: contrastText
                      anchors.centerIn: parent
                      text: parent.ratio.toFixed(1) + ":1 " + (parent.ratio >= 4.5 ? "✓" : "✗")
                      color: root.currentHex
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: CU.FORMATS

                  Rectangle {
                    required property string modelData
                    readonly property bool active: root.defaultFormat === modelData
                    width: chipText.implicitWidth + Style.spacing.md * 2
                    height: Style.space(26)
                    radius: root.cornerRadius / 2
                    color: (chipHover.containsMouse || active) ? root.selectedBackground : "transparent"
                    border.width: 1
                    border.color: root.border
                    opacity: chipHover.containsMouse ? 1 : (active ? 0.95 : 0.6)

                    Text {
                      id: chipText
                      anchors.centerIn: parent
                      text: modelData.toUpperCase()
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: chipHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setMode(parent.modelData)
                    }
                  }
                }
              }
            }
          }

          // ---- Chooser: Adobe-style harmony wheel, or classic SV box ----
          Row {
            width: parent.width
            spacing: Style.spacing.md

            Item {
              id: chooserLeft
              visible: root.chooserMode !== "image"
              width: root.chooserMode === "image" ? 0 : Style.space(190)
              height: root.chooserMode === "wheel"
                ? wheelCol.height
                : Math.max(Style.space(150), chooserRight.height)

              // Wheel mode: hue/saturation disc with the five harmony
              // markers riding on it, plus a brightness bar for the base.
              Column {
                id: wheelCol
                visible: root.chooserMode === "wheel"
                spacing: Style.spacing.md

                Item {
                  id: wheel
                  width: Style.space(190)
                  height: Style.space(190)

                  Canvas {
                    anchors.fill: parent
                    onPaint: {
                      var ctx = getContext("2d")
                      var cx = width / 2, cy = height / 2
                      var R = Math.min(cx, cy) - 2
                      ctx.clearRect(0, 0, width, height)
                      for (var a = 0; a < 360; a++) {
                        ctx.beginPath()
                        ctx.moveTo(cx, cy)
                        ctx.arc(cx, cy, R, (a - 0.6) * Math.PI / 180, (a + 1) * Math.PI / 180)
                        ctx.closePath()
                        ctx.fillStyle = "hsl(" + a + ", 100%, 50%)"
                        ctx.fill()
                      }
                      var grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, R)
                      grad.addColorStop(0, "rgba(255,255,255,1)")
                      grad.addColorStop(1, "rgba(255,255,255,0)")
                      ctx.beginPath()
                      ctx.arc(cx, cy, R, 0, 2 * Math.PI)
                      ctx.fillStyle = grad
                      ctx.fill()
                    }
                  }

                  Repeater {
                    model: root.paletteColors

                    Rectangle {
                      required property var modelData
                      readonly property real half: wheel.width / 2
                      x: half + Math.cos(modelData.h * Math.PI / 180) * modelData.s * (half - 2) - width / 2
                      y: half + Math.sin(modelData.h * Math.PI / 180) * modelData.s * (half - 2) - height / 2
                      width: Style.space(modelData.isBase ? 20 : 15)
                      height: width
                      radius: width / 2
                      color: modelData.hex
                      border.width: modelData.isBase ? 3 : 2
                      border.color: modelData.v > 0.55 ? "#000000" : "#ffffff"
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    property int dragSlot: 2

                    function slotAt(mx, my) {
                      var best = 2, bestD = 1e9
                      var half = wheel.width / 2, R = half - 2
                      for (var j = 0; j < root.paletteColors.length; j++) {
                        var p = root.paletteColors[j]
                        var px = half + Math.cos(p.h * Math.PI / 180) * p.s * R
                        var py = half + Math.sin(p.h * Math.PI / 180) * p.s * R
                        var d = (mx - px) * (mx - px) + (my - py) * (my - py)
                        if (d < bestD) { bestD = d; best = j }
                      }
                      return best
                    }

                    // Dragging any marker re-solves the base color so the
                    // other four snap back into the rule's geometry.
                    function applyAt(mx, my) {
                      var half = wheel.width / 2, R = half - 2
                      var dx = mx - half, dy = my - half
                      var h = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360
                      var s = Math.min(1, Math.sqrt(dx * dx + dy * dy) / R)
                      var base = CU.solveBaseFromSlot(root.harmonyRule, dragSlot, h, s, root.val)
                      root.hue = base.h
                      root.sat = base.s
                    }

                    onPressed: function(mouse) { dragSlot = slotAt(mouse.x, mouse.y); applyAt(mouse.x, mouse.y) }
                    onPositionChanged: function(mouse) { if (pressed) applyAt(mouse.x, mouse.y) }
                  }
                }

                Rectangle {
                  id: vBar
                  width: wheel.width
                  height: Style.space(16)
                  radius: root.cornerRadius / 2
                  border.width: 1
                  border.color: root.border
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#000000" }
                    GradientStop { position: 1; color: CU.toHex(CU.hsvToRgb({ h: root.hue, s: root.sat, v: 1 })) }
                  }

                  Rectangle {
                    x: root.val * vBar.width - width / 2
                    y: -Style.space(2)
                    width: Style.space(6)
                    height: vBar.height + Style.space(4)
                    radius: width / 2
                    color: "#ffffff"
                    border.width: 1
                    border.color: "#000000"
                  }

                  MouseArea {
                    anchors.fill: parent
                    function apply(mouse) { root.val = Math.max(0.04, Math.min(1, mouse.x / vBar.width)) }
                    onPressed: function(mouse) { apply(mouse) }
                    onPositionChanged: function(mouse) { if (pressed) apply(mouse) }
                  }
                }
              }

              // Box mode: the classic SV square.
              Rectangle {
                id: svBox
                visible: root.chooserMode === "box"
                width: Style.space(190)
                height: chooserLeft.height
                radius: root.cornerRadius / 2
                color: CU.toHex(CU.hsvToRgb({ h: root.hue, s: 1, v: 1 }))
                border.width: 1
                border.color: root.border
                clip: true

                Rectangle {
                  anchors.fill: parent
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                  }
                }
                Rectangle {
                  anchors.fill: parent
                  gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#ff000000" }
                  }
                }

                Rectangle {
                  x: root.sat * svBox.width - width / 2
                  y: (1 - root.val) * svBox.height - height / 2
                  width: Style.space(12)
                  height: Style.space(12)
                  radius: width / 2
                  color: "transparent"
                  border.width: 2
                  border.color: root.val > 0.5 ? "#000000" : "#ffffff"
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.CrossCursor
                  function apply(mouse) {
                    root.sat = Math.max(0, Math.min(1, mouse.x / svBox.width))
                    root.val = Math.max(0, Math.min(1, 1 - mouse.y / svBox.height))
                  }
                  onPressed: function(mouse) { apply(mouse) }
                  onPositionChanged: function(mouse) { if (pressed) apply(mouse) }
                }
              }
            }

            Column {
              id: chooserRight
              width: parent.width - chooserLeft.width - Style.spacing.md
              spacing: Style.spacing.md

              Row {
                spacing: Style.space(6)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Picker"
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: [{ k: "wheel", label: "󰝥 Wheel" }, { k: "box", label: "󰝤 Box" }]

                  Rectangle {
                    required property var modelData
                    readonly property bool active: root.chooserMode === modelData.k
                    width: modeText.implicitWidth + Style.spacing.md * 2
                    height: Style.space(24)
                    radius: root.cornerRadius / 2
                    color: (modeHover.containsMouse || active) ? root.selectedBackground : "transparent"
                    border.width: 1
                    border.color: root.border
                    opacity: active ? 1 : 0.6

                    Text {
                      id: modeText
                      anchors.centerIn: parent
                      text: parent.modelData.label
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: modeHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.service) root.service.setChooserMode(parent.modelData.k)
                    }
                  }
                }

                Rectangle {
                  readonly property bool active: root.chooserMode === "image"
                  width: pasteText.implicitWidth + Style.spacing.md * 2
                  height: Style.space(24)
                  radius: root.cornerRadius / 2
                  color: (pasteHover.containsMouse || active) ? root.selectedBackground : "transparent"
                  border.width: 1
                  border.color: root.border
                  opacity: active ? 1 : (pasteHover.containsMouse ? 1 : 0.6)

                  Text {
                    id: pasteText
                    anchors.centerIn: parent
                    text: "󰆒 Image"
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    id: pasteHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Every click re-parses the clipboard image; a successful
                    // extraction auto-switches into image mode.
                    onClicked: if (root.service) root.service.pasteImage()
                  }
                }
              }

              // Image mode: the extracted palette takes the chooser's place.
              Column {
                visible: root.chooserMode === "image"
                width: parent.width
                spacing: Style.spacing.md

                Row {
                  spacing: Style.spacing.md

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.imagePalette ? root.imagePalette.name : "No image yet"
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    visible: !!root.imagePalette
                    width: saveImgText.implicitWidth + Style.spacing.md * 2
                    height: Style.space(22)
                    radius: root.cornerRadius / 2
                    color: saveImgHover.containsMouse ? root.selectedBackground : "transparent"
                    border.width: 1
                    border.color: root.border
                    opacity: saveImgHover.containsMouse ? 1 : 0.6

                    Text {
                      id: saveImgText
                      anchors.centerIn: parent
                      text: "󰆓 Save"
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: saveImgHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.service && root.imagePalette) root.service.addHarmony(root.imagePalette.name, root.imagePalette.colors)
                    }
                  }
                }

                Text {
                  visible: !root.imagePalette
                  text: "Drop an image anywhere on this window — or copy one and hit 󰆒 Image — to pull its color palette."
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  width: parent.width
                  wrapMode: Text.WordWrap
                }

                Row {
                  visible: !!root.imagePalette
                  width: parent.width
                  spacing: Style.spacing.md

                  Rectangle {
                    id: thumbFrame
                    width: Style.space(132)
                    height: Style.space(84)
                    radius: root.cornerRadius / 2
                    color: root.selectedBackground
                    border.width: 1
                    border.color: root.border
                    clip: true

                    Image {
                      anchors.fill: parent
                      anchors.margins: 1
                      cache: false
                      asynchronous: true
                      fillMode: Image.PreserveAspectCrop
                      source: root.imagePalette && root.imagePalette.thumb ? "file://" + root.imagePalette.thumb : ""
                    }
                  }

                Flow {
                  width: parent.width - thumbFrame.width - Style.spacing.md
                  spacing: Style.space(6)

                  Repeater {
                    model: root.imagePalette ? root.imagePalette.colors : []

                    Rectangle {
                      required property string modelData
                      width: Style.space(38)
                      height: Style.space(38)
                      radius: root.cornerRadius / 2
                      color: modelData
                      border.width: imgHover.containsMouse ? 2 : 1
                      border.color: imgHover.containsMouse ? root.selectedText : root.border

                      Text {
                        anchors.centerIn: parent
                        visible: root.copiedFlash === parent.modelData
                        text: "✓"
                        color: CU.luminance(CU.parseHex(parent.modelData)) > 0.4 ? "#000000" : "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }

                      MouseArea {
                        id: imgHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onContainsMouseChanged: if (containsMouse) root.hoverLabel = root.fmtOf(parent.modelData) + " · click = copy · right-click = make base"
                        onClicked: function(mouse) {
                          if (mouse.button === Qt.RightButton) root.selectSwatch(parent.modelData)
                          else root.copyColor(parent.modelData, false)
                        }
                      }
                    }
                  }
                }
                }
              }

              // Harmony rules — wheel mode only, where the markers can show
              // where each color is pulled from. Labeled and spaced apart
              // from the picker-mode toggle so the two groups read as
              // different controls.
              Column {
                visible: root.chooserMode === "wheel"
                width: parent.width
                spacing: Style.space(4)

                Item { width: 1; height: Style.space(6) }

                Text {
                  text: "Harmony"
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

              Flow {
                width: parent.width
                spacing: Style.space(5)

                Repeater {
                  model: CU.HARMONY_RULES

                  Rectangle {
                    required property var modelData
                    readonly property bool active: root.harmonyRule === modelData.key
                    width: ruleText.implicitWidth + Style.spacing.md * 2
                    height: Style.space(24)
                    radius: root.cornerRadius / 2
                    color: (ruleHover.containsMouse || active) ? root.selectedBackground : "transparent"
                    border.width: 1
                    border.color: root.border
                    opacity: active ? 1 : 0.6

                    Text {
                      id: ruleText
                      anchors.centerIn: parent
                      text: parent.modelData.name
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: ruleHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.harmonyRule = parent.modelData.key
                    }
                  }
                }
              }

              }

              // The 5-color palette the current rule produces.
              Row {
                visible: root.chooserMode === "wheel"
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.paletteColors

                  Column {
                    id: palItem
                    required property var modelData
                    width: (chooserRight.width - Style.space(6) * 4) / 5
                    spacing: Style.space(3)

                    Rectangle {
                      width: parent.width
                      height: Style.space(46)
                      radius: root.cornerRadius / 2
                      color: palItem.modelData.hex
                      border.width: palItem.modelData.isBase || palHover.containsMouse ? 2 : 1
                      border.color: palItem.modelData.isBase ? root.selectedText
                        : palHover.containsMouse ? root.selectedText : root.border

                      Text {
                        anchors.centerIn: parent
                        visible: root.copiedFlash === palItem.modelData.hex
                        text: "✓"
                        color: palItem.modelData.v > 0.55 ? "#000000" : "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                      }

                      MouseArea {
                        id: palHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) root.hoverLabel = root.fmtOf(palItem.modelData.hex) + " · click to copy"
                        onClicked: root.copyColor(palItem.modelData.hex, false)
                      }
                    }

                    Text {
                      width: parent.width
                      text: root.fmtOf(palItem.modelData.hex)
                      color: root.foreground
                      opacity: palItem.modelData.isBase ? 1 : 0.6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }
                }
              }

              // Save the palette currently showing above.
              Rectangle {
                visible: root.chooserMode === "wheel"
                width: saveText.implicitWidth + Style.spacing.md * 2
                height: Style.space(24)
                radius: root.cornerRadius / 2
                color: saveHover.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.border
                opacity: saveHover.containsMouse ? 1 : 0.65

                Text {
                  id: saveText
                  anchors.centerIn: parent
                  text: "󰆓 Save palette"
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: saveHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.service) return
                    var colors = []
                    for (var j = 0; j < root.paletteColors.length; j++) colors.push(root.paletteColors[j].hex)
                    root.service.addHarmony(root.harmonyRule, colors)
                  }
                }
              }

              // Box mode keeps the plain hue bar.
              Rectangle {
                id: hueBar
                visible: root.chooserMode === "box"
                width: parent.width
                height: Style.space(22)
                radius: root.cornerRadius / 2
                border.width: 1
                border.color: root.border
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.000; color: "#ff0000" }
                  GradientStop { position: 0.167; color: "#ffff00" }
                  GradientStop { position: 0.333; color: "#00ff00" }
                  GradientStop { position: 0.500; color: "#00ffff" }
                  GradientStop { position: 0.667; color: "#0000ff" }
                  GradientStop { position: 0.833; color: "#ff00ff" }
                  GradientStop { position: 1.000; color: "#ff0000" }
                }

                Rectangle {
                  x: (root.hue / 360) * hueBar.width - width / 2
                  y: -Style.space(2)
                  width: Style.space(6)
                  height: hueBar.height + Style.space(4)
                  radius: width / 2
                  color: "#ffffff"
                  border.width: 1
                  border.color: "#000000"
                }

                MouseArea {
                  anchors.fill: parent
                  function apply(mouse) { root.hue = Math.max(0, Math.min(359.9, mouse.x / hueBar.width * 360)) }
                  onPressed: function(mouse) { apply(mouse) }
                  onPositionChanged: function(mouse) { if (pressed) apply(mouse) }
                }
              }

              // Box mode brings back the compact list-style harmonies — a
              // couple of colors per family, lighter than the wheel's
              // five-slot palette. Left-click copies; right-click makes base.
              // Tight row spacing so the families read as one group.
              Column {
                visible: root.chooserMode === "box"
                spacing: Style.space(3)

              Repeater {
                model: root.chooserMode === "box" ? CU.harmonies(root.currentHex) : []

                Row {
                  id: boxHarmRow
                  required property var modelData
                  spacing: Style.space(6)

                  Text {
                    width: Style.space(118)
                    anchors.verticalCenter: parent.verticalCenter
                    text: boxHarmRow.modelData.name
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Repeater {
                    model: boxHarmRow.modelData.colors

                    Rectangle {
                      required property string modelData
                      width: Style.space(22)
                      height: Style.space(22)
                      radius: root.cornerRadius / 2
                      color: modelData
                      border.width: boxHarmHover.containsMouse ? 2 : 1
                      border.color: boxHarmHover.containsMouse ? root.selectedText : root.border

                      Text {
                        anchors.centerIn: parent
                        visible: root.copiedFlash === parent.modelData
                        text: "✓"
                        color: CU.luminance(CU.parseHex(parent.modelData)) > 0.4 ? "#000000" : "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      MouseArea {
                        id: boxHarmHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onContainsMouseChanged: if (containsMouse) root.hoverLabel = root.fmtOf(parent.modelData) + " · click = copy · right-click = make base"
                        onClicked: function(mouse) {
                          if (mouse.button === Qt.RightButton) root.selectSwatch(parent.modelData)
                          else root.copyColor(parent.modelData, false)
                        }
                      }
                    }
                  }
                }
              }
              }
            }
          }

          // ---- Pinned ----
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.pinned.length > 0

            Text {
              text: "Pinned"
              color: root.selectedText
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.pinned

                Rectangle {
                  required property string modelData
                  width: root.swatchSize
                  height: root.swatchSize
                  radius: root.cornerRadius / 2
                  color: modelData
                  border.width: pinnedHover.containsMouse ? 2 : 1
                  border.color: pinnedHover.containsMouse ? root.selectedText : root.border

                  MouseArea {
                    id: pinnedHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.hoverLabel = parent.modelData
                    onClicked: root.selectSwatch(parent.modelData)
                  }
                }
              }
            }
          }

          // ---- History ----
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: root.history.length > 0 ? "History   (󰈊 = screen pick)" : "History — pick a color to start"
              color: root.selectedText
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.history.slice(0, 20)

                Rectangle {
                  required property var modelData
                  required property int index
                  readonly property bool fromPick: modelData.src === "pick"
                  width: root.swatchSize
                  height: root.swatchSize
                  radius: root.cornerRadius / 2
                  color: modelData.hex

                  // Screen picks wear a tiny eyedropper; studio choices are
                  // plain. The glyph flips black/white by swatch luminance.
                  Text {
                    visible: parent.fromPick
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(2)
                    text: "󰈊"
                    color: CU.luminance(CU.parseHex(parent.modelData.hex)) > 0.4 ? "#000000" : "#ffffff"
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  border.width: histHover.containsMouse ? 2 : 1
                  border.color: histHover.containsMouse ? root.selectedText : root.border

                  MouseArea {
                    id: histHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.hoverLabel = parent.modelData.hex
                      + (parent.fromPick ? " · picked from screen" : " · chosen in studio")
                    onClicked: root.selectSwatch(parent.modelData.hex)
                  }

                  Rectangle {
                    visible: histHover.containsMouse
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -Style.space(4)
                    width: Style.space(14)
                    height: Style.space(14)
                    radius: width / 2
                    color: root.background
                    border.width: 1
                    border.color: root.border

                    Text {
                      anchors.centerIn: parent
                      text: "✕"
                      color: root.foreground
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.removeFromHistory(parent.parent.index)
                    }
                  }
                }
              }
            }
          }

          // ---- Saved harmonies: click a color to copy it (never selects).
          // Each set is a compact card — name on top, colors under — so two
          // or three wrap per row.
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.savedHarmonies.length > 0

            Text {
              text: "Saved harmonies"
              color: root.selectedText
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Flow {
              width: parent.width
              // Flow's spacing runs both axes, so keep it small (the row
              // gap) and let each card carry its own horizontal margin.
              spacing: Style.space(6)

              Repeater {
                model: root.savedHarmonies

                Item {
                  id: savedRow
                  required property var modelData
                  required property int index
                  width: savedCard.width + Style.space(16)
                  height: savedCard.height

                  Column {
                  id: savedCard
                  spacing: Style.space(2)

                  Row {
                    spacing: Style.space(4)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: savedRow.modelData.rule
                      color: root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(14)
                      height: Style.space(14)
                      radius: width / 2
                      color: delHover.containsMouse ? root.selectedBackground : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: root.foreground
                        opacity: delHover.containsMouse ? 1 : 0.4
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        id: delHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service) root.service.removeHarmony(savedRow.index)
                      }
                    }
                  }

                  Row {
                    spacing: Style.space(4)

                    Repeater {
                      model: savedRow.modelData.colors

                      Rectangle {
                        required property string modelData
                        width: root.swatchSize
                        height: root.swatchSize
                        radius: root.cornerRadius / 2
                        color: modelData
                        border.width: savedHover.containsMouse ? 2 : 1
                        border.color: savedHover.containsMouse ? root.selectedText : root.border

                        Text {
                          anchors.centerIn: parent
                          visible: root.copiedFlash === parent.modelData
                          text: "✓"
                          color: CU.luminance(CU.parseHex(parent.modelData)) > 0.4 ? "#000000" : "#ffffff"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }

                        MouseArea {
                          id: savedHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          acceptedButtons: Qt.LeftButton | Qt.RightButton
                          onContainsMouseChanged: if (containsMouse) root.hoverLabel = root.fmtOf(parent.modelData) + " · click = copy · right-click = make base"
                          // Left copies the code; right loads it as the
                          // working color so it can seed another harmony.
                          onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) root.selectSwatch(parent.modelData)
                            else root.copyColor(parent.modelData, false)
                          }
                        }
                      }
                    }
                  }
                }
                }
              }
            }
          }

          // ---- Theme palette ----
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.themeColors.length > 0

            Text {
              text: "Theme palette"
              color: root.selectedText
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.themeColors

                Rectangle {
                  required property var modelData
                  width: root.swatchSize
                  height: root.swatchSize
                  radius: root.cornerRadius / 2
                  color: modelData.hex
                  border.width: themeHover.containsMouse ? 2 : 1
                  border.color: themeHover.containsMouse ? root.selectedText : root.border

                  MouseArea {
                    id: themeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.hoverLabel = parent.modelData.name + "  " + parent.modelData.hex
                    onClicked: root.chooseSwatch(parent.modelData.hex)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: (root.hoverLabel ? root.hoverLabel + "   ·   " : "")
              + "history/theme = select · harmony or top-left = copy · chips = format · Esc close"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
