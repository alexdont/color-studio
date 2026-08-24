import QtQuick
import Quickshell
import Quickshell.Io
import "ColorUtils.js" as CU

// Headless singleton that owns the studio's shared state — history, pins,
// default format — and the screen-pick process. It is the ONLY writer of
// state.json: the bar widget and the overlay both read these properties and
// mutate through these functions, so a pick can never race an overlay edit
// and overwrite the file with a stale copy.
Item {
  id: root

  property var shell: null
  property var settings: ({})

  readonly property string pluginId: "io.github.alexdont.color-studio"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/" + pluginId

  property var history: []
  property var pinned: []
  property string defaultFormat: "hex"
  property string currentColor: ""
  // Last-used chooser mode (wheel/box/image), restored on reopen.
  property string chooserMode: "wheel"
  property var savedHarmonies: []
  // Palette pulled from a dropped or pasted image: { name, colors: [hex] }
  property var imagePalette: null
  readonly property string lastColor: history.length > 0 ? history[0].hex : ""

  function loadState(raw) {
    var history = [], pinned = [], fmt = "hex", cur = "", harmonies = [], mode = "wheel"
    try {
      var p = JSON.parse(raw)
      history = CU.normalizeHistory(p.history)
      if (Array.isArray(p.pinned)) pinned = p.pinned
      if (typeof p.defaultFormat === "string") fmt = p.defaultFormat
      if (typeof p.currentColor === "string" && CU.parseHex(p.currentColor)) cur = p.currentColor
      if (p.chooserMode === "box" || p.chooserMode === "image") mode = p.chooserMode
      if (p.imagePalette && typeof p.imagePalette.name === "string" && Array.isArray(p.imagePalette.colors))
        root.imagePalette = { name: p.imagePalette.name,
          colors: p.imagePalette.colors.filter(function(c) { return !!CU.parseHex(c) }),
          thumb: typeof p.imagePalette.thumb === "string" ? p.imagePalette.thumb : "" }
      if (Array.isArray(p.savedHarmonies)) {
        for (var j = 0; j < p.savedHarmonies.length; j++) {
          var e = p.savedHarmonies[j]
          if (e && typeof e.rule === "string" && Array.isArray(e.colors) && e.colors.length > 0)
            harmonies.push({ rule: e.rule, colors: e.colors.filter(function(c) { return !!CU.parseHex(c) }) })
        }
      }
    } catch (e) {}
    root.history = history
    root.pinned = pinned
    root.defaultFormat = fmt
    root.currentColor = cur
    root.chooserMode = mode
    root.savedHarmonies = harmonies
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      version: 1, history: root.history, pinned: root.pinned,
      defaultFormat: root.defaultFormat, currentColor: root.currentColor,
      savedHarmonies: root.savedHarmonies, imagePalette: root.imagePalette,
      chooserMode: root.chooserMode
    }, null, 2) + "\n")
  }

  function addHistory(hex, src) {
    var rgb = CU.parseHex(hex)
    if (!rgb) return
    hex = CU.toHex(rgb)
    var hist = root.history.slice()
    if (hist[0] && hist[0].hex === hex) return
    hist.unshift({ hex: hex, src: src === "pick" ? "pick" : "studio" })
    if (hist.length > 50) hist = hist.slice(0, 50)
    root.history = hist
    root.saveState()
  }

  function removeHistory(index) {
    var hist = root.history.slice()
    hist.splice(index, 1)
    root.history = hist
    root.saveState()
  }

  function togglePin(hex) {
    var pins = root.pinned.slice()
    var idx = pins.indexOf(hex)
    if (idx >= 0) pins.splice(idx, 1)
    else pins.unshift(hex)
    root.pinned = pins
    root.saveState()
  }

  // The studio's working color, persisted so the popup reopens on whatever
  // was last selected from history, pins, or the theme strip.
  function setCurrentColor(hex) {
    var rgb = CU.parseHex(hex)
    if (!rgb) return
    root.currentColor = CU.toHex(rgb)
    root.saveState()
  }

  // Leaving image mode discards the extracted palette, so re-entering
  // image mode re-parses whatever is on the clipboard at that moment.
  function setChooserMode(mode) {
    if (mode !== "image" && root.chooserMode === "image") root.imagePalette = null
    root.chooserMode = mode
    root.saveState()
  }

  // ---- image → palette ----------------------------------------------------

  function extractFromImage(path) {
    if (extractProc.running) return
    extractProc.imagePath = path
    extractProc.command = ["magick", path, "-resize", "100x100^", "-colors", "16", "-depth", "8", "-format", "%c", "histogram:info:"]
    extractProc.running = true
  }

  function pasteImage() {
    if (!clipImage.running) clipImage.running = true
  }

  function addHarmony(rule, colors) {
    var list = root.savedHarmonies.slice()
    if (list[0] && JSON.stringify(list[0].colors) === JSON.stringify(colors)) return
    list.unshift({ rule: rule, colors: colors })
    if (list.length > 20) list = list.slice(0, 20)
    root.savedHarmonies = list
    root.saveState()
  }

  function removeHarmony(index) {
    var list = root.savedHarmonies.slice()
    list.splice(index, 1)
    root.savedHarmonies = list
    root.saveState()
  }

  function setDefaultFormat(fmt) {
    root.defaultFormat = fmt
    root.saveState()
  }

  // hyprpicker prints its result only when stdout is a TTY — from inside the
  // shell the pipe stays empty (verified). So the pick runs in autocopy mode
  // and the result is read back off the clipboard, compared against the
  // clipboard from before the pick so a cancelled lens changes nothing.
  property string clipBeforePick: ""

  function pick() {
    if (clipBefore.running || picker.running || clipAfter.running) return
    // The studio and the lens are both exclusive overlay surfaces — close
    // ours first or hyprpicker loses the fight and the pick silently fails.
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    clipBefore.running = true
  }

  function toggleStudio() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, "{}"])
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
    onFileChanged: reload()
  }

  Process {
    id: clipBefore
    // pkill first: a stray hyprpicker (ours from a previous shell session,
    // or the built-in binding's) holds the layer surface and would make the
    // new lens silently fail — same defense the stock Super+Print uses.
    command: ["sh", "-c", "pkill hyprpicker 2>/dev/null; wl-paste -n 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.clipBeforePick = text
        picker.running = true
      }
    }
  }

  Process {
    id: picker
    command: ["hyprpicker", "-a", "-f", "hex", "-b", "-q", "-l"]
    onExited: function(code, status) { clipAfter.running = true }
  }

  Process {
    id: clipAfter
    command: ["sh", "-c", "wl-paste -n 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        var rgb = CU.parseHex(text.trim())
        if (!rgb || text === root.clipBeforePick) return // cancelled
        var out = CU.format(rgb, root.defaultFormat)
        // A fresh pick becomes the working color too, so the studio's wheel
        // and harmonies open on it. addHistory persists both in one save.
        root.currentColor = CU.toHex(rgb)
        root.addHistory(CU.toHex(rgb), "pick")
        // A fresh pick means "work with THIS color now": leave image mode
        // (which clears the image palette) and land back on the wheel.
        if (root.chooserMode === "image") root.setChooserMode("wheel")
        Quickshell.execDetached(["wl-copy", out])
        Quickshell.execDetached(["omarchy-notification-send", "-e", "-u", "low", "Color picked", out + " copied"])
      }
    }
  }

  Process {
    id: extractProc
    property string imagePath: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = []
        var lines = text.split("\n")
        for (var j = 0; j < lines.length; j++) {
          var m = lines[j].match(/^\s*(\d+):.*#([0-9A-Fa-f]{6})/)
          if (m) rows.push({ n: parseInt(m[1]), hex: "#" + m[2].toLowerCase() })
        }
        if (rows.length === 0) {
          Quickshell.execDetached(["omarchy-notification-send", "-e", "-u", "critical", "Color Studio", "Could not read a palette from that image"])
          return
        }
        rows.sort(function(a, b) { return b.n - a.n })
        var colors = [], seen = {}
        for (var k = 0; k < rows.length && colors.length < 16; k++) {
          if (seen[rows[k].hex]) continue
          seen[rows[k].hex] = true
          colors.push(rows[k].hex)
        }
        var name = extractProc.imagePath.split("/").pop()
        // Render a small persistent thumbnail into the state dir — pasted
        // sources get deleted from /tmp, so the preview needs its own copy.
        Quickshell.execDetached(["sh", "-c", "rm -f '" + root.stateDir + "'/thumb-*.png"])
        var thumb = root.stateDir + "/thumb-" + Date.now() + ".png"
        thumbProc.pendingPalette = { name: name, colors: colors, thumb: thumb }
        thumbProc.srcPath = extractProc.imagePath
        thumbProc.command = ["magick", extractProc.imagePath, "-resize", "440x", thumb]
        thumbProc.running = true
      }
    }
  }

  Process {
    id: thumbProc
    property var pendingPalette: null
    property string srcPath: ""
    onExited: function(code, status) {
      var p = thumbProc.pendingPalette
      if (!p) return
      if (code !== 0) p.thumb = ""
      root.imagePalette = p
      thumbProc.pendingPalette = null
      root.saveState()
      // Clipboard pastes are materialized under /tmp — remove ours once
      // read so they never accumulate. Dropped/copied real files are kept.
      if (thumbProc.srcPath.indexOf("/tmp/colorstudio-") === 0)
        Quickshell.execDetached(["rm", "-f", thumbProc.srcPath])
    }
  }

  // Materialize a clipboard image (or a copied file path) into a readable
  // file, then extract. Prints nothing when the clipboard holds neither.
  Process {
    id: clipImage
    command: ["sh", "-c", "if wl-paste -l 2>/dev/null | grep -qi '^image/'; then f=$(mktemp /tmp/colorstudio-XXXXXX.png); wl-paste --type image/png > \"$f\" 2>/dev/null && [ -s \"$f\" ] && echo \"$f\"; else p=$(wl-paste -n 2>/dev/null | head -1); p=\"${p#file://}\"; [ -f \"$p\" ] && echo \"$p\"; fi"]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = text.trim()
        if (path) root.extractFromImage(path)
        else Quickshell.execDetached(["omarchy-notification-send", "-e", "-u", "low", "Color Studio", "Clipboard has no image or image path"])
      }
    }
  }

  // Bindable from Hyprland: omarchy-shell colorstudio pick / toggle
  IpcHandler {
    target: "colorstudio"
    function pick(): void { root.pick() }
    function toggle(): void { root.toggleStudio() }
  }
}
