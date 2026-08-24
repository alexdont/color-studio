// Pure-JS color math: parsing, format output, harmonies, WCAG contrast,
// and OKLCH via Björn Ottosson's OKLab reference matrices. No dependencies.
.pragma library

function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v }

// ---- parse / basic conversions ------------------------------------------

function parseHex(s) {
  if (!s) return null
  var m = String(s).trim().match(/^#?([0-9a-fA-F]{6})$/)
  if (!m) return null
  var n = parseInt(m[1], 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

function toHex(rgb) {
  var h = function(v) { return ("0" + Math.round(clamp(v, 0, 255)).toString(16)).slice(-2) }
  return "#" + h(rgb.r) + h(rgb.g) + h(rgb.b)
}

function rgbToHsl(rgb) {
  var r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var l = (max + min) / 2, h = 0, s = 0
  var d = max - min
  if (d !== 0) {
    s = d / (1 - Math.abs(2 * l - 1))
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  if (h < 0) h += 360
  return { h: h, s: s, l: l }
}

function hslToRgb(hsl) {
  var h = ((hsl.h % 360) + 360) % 360, s = clamp(hsl.s, 0, 1), l = clamp(hsl.l, 0, 1)
  var c = (1 - Math.abs(2 * l - 1)) * s
  var x = c * (1 - Math.abs((h / 60) % 2 - 1))
  var m = l - c / 2
  var rp = [c, x, 0, 0, x, c][Math.floor(h / 60)]
  var gp = [x, c, c, x, 0, 0][Math.floor(h / 60)]
  var bp = [0, 0, x, c, c, x][Math.floor(h / 60)]
  return { r: (rp + m) * 255, g: (gp + m) * 255, b: (bp + m) * 255 }
}

function rgbToHsv(rgb) {
  var r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var d = max - min, h = 0
  if (d !== 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  if (h < 0) h += 360
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function hsvToRgb(hsv) {
  var l = hsv.v * (1 - hsv.s / 2)
  var s2 = (l === 0 || l === 1) ? 0 : (hsv.v - l) / Math.min(l, 1 - l)
  return hslToRgb({ h: hsv.h, s: s2, l: l })
}

// ---- OKLCH (Ottosson reference implementation) --------------------------

function srgbToLinear(c) {
  c = c / 255
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

function rgbToOklch(rgb) {
  var r = srgbToLinear(rgb.r), g = srgbToLinear(rgb.g), b = srgbToLinear(rgb.b)
  var l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  var m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  var s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
  var l_ = Math.cbrt(l), m_ = Math.cbrt(m), s_ = Math.cbrt(s)
  var L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  var A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  var B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  var C = Math.sqrt(A * A + B * B)
  var H = Math.atan2(B, A) * 180 / Math.PI
  if (H < 0) H += 360
  return { L: L, C: C, H: H }
}

// ---- WCAG contrast -------------------------------------------------------

function luminance(rgb) {
  return 0.2126 * srgbToLinear(rgb.r) + 0.7152 * srgbToLinear(rgb.g) + 0.0722 * srgbToLinear(rgb.b)
}

function contrastRatio(rgb1, rgb2) {
  var a = luminance(rgb1), b = luminance(rgb2)
  var hi = Math.max(a, b), lo = Math.min(a, b)
  return (hi + 0.05) / (lo + 0.05)
}

// ---- formatted output ----------------------------------------------------

var FORMATS = ["hex", "rgb", "rgba", "hsl", "hsv", "oklch"]

function format(rgb, fmt) {
  var r = Math.round(rgb.r), g = Math.round(rgb.g), b = Math.round(rgb.b)
  if (fmt === "hex") return toHex(rgb)
  if (fmt === "rgb") return "rgb(" + r + ", " + g + ", " + b + ")"
  if (fmt === "rgba") return "rgba(" + r + ", " + g + ", " + b + ", 1)"
  if (fmt === "hsl") {
    var hsl = rgbToHsl(rgb)
    return "hsl(" + Math.round(hsl.h) + ", " + Math.round(hsl.s * 100) + "%, " + Math.round(hsl.l * 100) + "%)"
  }
  if (fmt === "hsv") {
    var hsv = rgbToHsv(rgb)
    return "hsv(" + Math.round(hsv.h) + ", " + Math.round(hsv.s * 100) + "%, " + Math.round(hsv.v * 100) + "%)"
  }
  if (fmt === "oklch") {
    var ok = rgbToOklch(rgb)
    return "oklch(" + Math.round(ok.L * 100) + "% " + ok.C.toFixed(3) + " " + Math.round(ok.H) + ")"
  }
  return toHex(rgb)
}

// ---- harmonies -----------------------------------------------------------

// Each returns a list of hex strings derived from the base (hex). The base
// itself is not repeated in the results.
function harmonies(hex) {
  var rgb = parseHex(hex)
  if (!rgb) return []
  var hsl = rgbToHsl(rgb)
  var rot = function(deg) { return toHex(hslToRgb({ h: hsl.h + deg, s: hsl.s, l: hsl.l })) }
  var lit = function(l) { return toHex(hslToRgb({ h: hsl.h, s: hsl.s, l: clamp(l, 0.04, 0.96) })) }
  // A hue shifted AND stepped in lightness — used to spread the complement
  // into a usable mini-palette instead of a single opposite.
  var rotLit = function(deg, dl) {
    return toHex(hslToRgb({ h: hsl.h + deg, s: hsl.s, l: clamp(hsl.l + dl, 0.04, 0.96) }))
  }
  return [
    { name: "Complementary", colors: [rotLit(180, -0.22), rotLit(180, -0.11), rot(180), rotLit(180, 0.11), rotLit(180, 0.22)] },
    { name: "Split-complementary", colors: [rot(150), rotLit(150, 0.12), rot(210), rotLit(210, 0.12)] },
    { name: "Analogous", colors: [rot(-30), rot(-15), rot(15), rot(30)] },
    { name: "Triadic", colors: [rot(120), rotLit(120, 0.12), rot(240), rotLit(240, 0.12)] },
    { name: "Tetradic", colors: [rot(90), rot(180), rot(270)] },
    { name: "Shades & tints", colors: [lit(hsl.l - 0.3), lit(hsl.l - 0.15), lit(hsl.l + 0.15), lit(hsl.l + 0.3)] }
  ]
}

// History entries are {hex, src} with src "pick" (screen eyedropper) or
// "studio" (chosen inside the overlay). Older state files stored plain hex
// strings — normalize those to screen picks.
function normalizeHistory(list) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var j = 0; j < list.length; j++) {
    var e = list[j]
    if (typeof e === "string") { var rgb = parseHex(e); if (rgb) out.push({ hex: toHex(rgb), src: "pick" }) }
    else if (e && typeof e.hex === "string") { var rgb2 = parseHex(e.hex); if (rgb2) out.push({ hex: toHex(rgb2), src: e.src === "studio" ? "studio" : "pick" }) }
  }
  return out
}

// ---- Adobe-style harmony rules --------------------------------------------
// Every rule yields exactly 5 slots; the BASE color is slot 2 (the middle,
// as on color.adobe.com). A slot is {dh, ds, db}: hue offset in degrees and
// multipliers on the base color's saturation and value. Dragging any slot's
// marker on the wheel re-solves the base via solveBaseFromSlot, which snaps
// every other marker back into the rule's geometry.
var HARMONY_RULES = [
  { key: "analogous", name: "Analogous", slots: [
    { dh: -30, ds: 0.9,  db: 0.85 }, { dh: -15, ds: 1, db: 1 }, { dh: 0, ds: 1, db: 1 },
    { dh: 15,  ds: 1,    db: 1 },    { dh: 30,  ds: 0.9, db: 0.85 } ] },
  { key: "monochromatic", name: "Monochromatic", slots: [
    { dh: 0, ds: 1,    db: 0.5 },  { dh: 0, ds: 0.55, db: 1 },   { dh: 0, ds: 1, db: 1 },
    { dh: 0, ds: 0.55, db: 0.65 }, { dh: 0, ds: 1,    db: 0.8 } ] },
  { key: "complementary", name: "Complementary", slots: [
    { dh: 0, ds: 1, db: 0.45 },   { dh: 0, ds: 0.65, db: 1 },  { dh: 0, ds: 1, db: 1 },
    { dh: 180, ds: 1, db: 1 },    { dh: 180, ds: 1, db: 0.55 } ] },
  { key: "split", name: "Split-comp", slots: [
    { dh: 0, ds: 1, db: 0.5 },    { dh: 0, ds: 0.65, db: 1 },  { dh: 0, ds: 1, db: 1 },
    { dh: 150, ds: 1, db: 1 },    { dh: 210, ds: 1, db: 1 } ] },
  { key: "triad", name: "Triad", slots: [
    { dh: 120, ds: 1, db: 1 },    { dh: 120, ds: 0.55, db: 1 }, { dh: 0, ds: 1, db: 1 },
    { dh: 240, ds: 1, db: 1 },    { dh: 240, ds: 0.55, db: 0.8 } ] },
  { key: "square", name: "Square", slots: [
    { dh: 90, ds: 1, db: 1 },     { dh: 180, ds: 1, db: 1 },   { dh: 0, ds: 1, db: 1 },
    { dh: 270, ds: 1, db: 1 },    { dh: 90, ds: 0.55, db: 0.85 } ] },
  { key: "compound", name: "Compound", slots: [
    { dh: 30, ds: 1, db: 1 },     { dh: 30, ds: 0.55, db: 0.9 }, { dh: 0, ds: 1, db: 1 },
    { dh: 210, ds: 1, db: 1 },    { dh: 180, ds: 0.6, db: 0.9 } ] },
  { key: "shades", name: "Shades", slots: [
    { dh: 0, ds: 1, db: 0.4 },    { dh: 0, ds: 1, db: 0.7 },   { dh: 0, ds: 1, db: 1 },
    { dh: 0, ds: 1, db: 0.55 },   { dh: 0, ds: 1, db: 0.85 } ] }
]

function ruleByKey(key) {
  for (var j = 0; j < HARMONY_RULES.length; j++)
    if (HARMONY_RULES[j].key === key) return HARMONY_RULES[j]
  return HARMONY_RULES[2]
}

function palette(ruleKey, base) {
  var rule = ruleByKey(ruleKey)
  var out = []
  for (var j = 0; j < rule.slots.length; j++) {
    var sl = rule.slots[j]
    var hsv = {
      h: ((base.h + sl.dh) % 360 + 360) % 360,
      s: clamp(base.s * sl.ds, 0, 1),
      v: clamp(base.v * sl.db, 0.04, 1)
    }
    out.push({ h: hsv.h, s: hsv.s, v: hsv.v, hex: toHex(hsvToRgb(hsv)), isBase: j === 2 })
  }
  return out
}

// Dragged slot j landed at wheel position (h, s): find the base that puts it
// there under the rule, so the other four markers realign around the drag.
function solveBaseFromSlot(ruleKey, slotIndex, h, s, v) {
  var sl = ruleByKey(ruleKey).slots[slotIndex]
  return {
    h: ((h - sl.dh) % 360 + 360) % 360,
    s: clamp(sl.ds > 0.01 ? s / sl.ds : s, 0, 1),
    v: v
  }
}
