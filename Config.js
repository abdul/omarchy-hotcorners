.pragma library

// Shared config contract for the service and the settings GUI. Both read the
// same file; the GUI writes it and the service picks the change up through
// FileView's watcher, so nothing needs a shell restart.

var PATH_SUFFIX = "/.config/omarchy/hotcorners.json"

var CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"]

var CORNER_LABELS = {
  "top-left": "Top left",
  "top-right": "Top right",
  "bottom-left": "Bottom left",
  "bottom-right": "Bottom right"
}

// Sentinel for the free-text option in the preset dropdown. Never stored.
var CUSTOM = "__custom__"
var STAY_AWAKE = "__stay_awake_corner__"

// Presets offered by the GUI. Every command here is a real Omarchy command;
// "" is the disabled state.
var PRESETS = [
  { label: "Nothing", value: "" },

  // The macOS hot corner actions, mapped to their Omarchy equivalents.
  { label: "Lock screen", value: "omarchy system lock" },
  { label: "Start screen saver", value: "omarchy launch screensaver" },
  { label: "Stay awake", value: STAY_AWAKE },
  { label: "Put display to sleep", value: "hyprctl dispatch 'hl.dsp.dpms(\"off\")'" },
  { label: "Notification centre", value: "omarchy-shell notifications showHistory" },
  { label: "Launchpad (apps menu)", value: "omarchy menu toggle apps" },

  // Workspaces and windows. Hyprland has no window overview of its own, so
  // there is nothing to map Mission Control or Application Windows onto;
  // these are the navigation dispatchers it does provide. Hyprland 0.56 takes
  // Lua expressions, not the classic "dispatcher arg" form.
  { label: "Next workspace", value: "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'" },
  { label: "Previous workspace", value: "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'" },
  { label: "Last used workspace", value: "hyprctl dispatch 'hl.dsp.focus({ workspace = \"previous\" })'" },
  { label: "Toggle scratchpad", value: "hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"scratchpad\")'" },
  { label: "Cycle windows", value: "hyprctl dispatch 'hl.dsp.window.cycle_next()'" },

  // The rest of what Omarchy offers.
  { label: "Omarchy menu", value: "omarchy menu toggle" },
  { label: "System menu", value: "omarchy menu toggle system" },
  { label: "Clipboard history", value: "omarchy menu clipboard" },
  { label: "Emoji picker", value: "omarchy menu emoji" },
  { label: "Screenshot a region", value: "omarchy capture screenshot region" },
  { label: "Toggle night light", value: "omarchy toggle nightlight" },

  { label: "Custom command…", value: CUSTOM }
]

var LIMITS = {
  triggerSize: { min: 1, max: 40, def: 4 },
  dwellMs: { min: 0, max: 3000, def: 400 },
  cooldownMs: { min: 0, max: 10000, def: 1500 }
}

function defaults() {
  var corners = {}
  for (var i = 0; i < CORNERS.length; i++) corners[CORNERS[i]] = { action: "" }
  return {
    version: 1,
    triggerSize: LIMITS.triggerSize.def,
    dwellMs: LIMITS.dwellMs.def,
    cooldownMs: LIMITS.cooldownMs.def,
    shortcut: "",
    requireSuper: false,
    suppressFullscreen: true,
    glow: true,
    corners: corners
  }
}

// ------------------------------------------------------------- shortcuts
//
// Qt modifier bits, hardcoded because this is a .pragma library with no QML
// context to read Qt.* from.
var MOD_SHIFT = 0x02000000
var MOD_CTRL = 0x04000000
var MOD_ALT = 0x08000000
var MOD_META = 0x10000000

var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023]

var SPECIAL_KEYS = {
  0x20: "SPACE", 0x01000004: "RETURN", 0x01000005: "RETURN", 0x01000001: "TAB",
  0x2c: "COMMA", 0x2e: "PERIOD", 0x2f: "SLASH", 0x3b: "SEMICOLON",
  0x27: "APOSTROPHE", 0x5b: "BRACKETLEFT", 0x5d: "BRACKETRIGHT",
  0x2d: "MINUS", 0x3d: "EQUAL", 0x60: "GRAVE", 0x5c: "BACKSLASH",
  0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x01000016: "PRIOR", 0x01000017: "NEXT", 0x01000010: "HOME", 0x01000011: "END",
  0x01000003: "BACKSPACE", 0x01000007: "DELETE", 0x01000006: "INSERT"
}

function isModifierKey(key) {
  return MODIFIER_KEYS.indexOf(key) !== -1
}

function keyName(key) {
  if (key >= 0x41 && key <= 0x5a) return String.fromCharCode(key)
  if (key >= 0x30 && key <= 0x39) return String.fromCharCode(key)
  if (key >= 0x01000030 && key <= 0x0100003b) return "F" + (key - 0x01000030 + 1)
  return SPECIAL_KEYS[key] || ""
}

// Builds "SUPER + SHIFT + H" from a Qt key event. Returns "" for anything
// unusable — an unknown key, or a bare key with no modifier, which would
// swallow ordinary typing system-wide.
function shortcutFrom(modifiers, key) {
  var name = keyName(key)
  if (!name) return ""
  var parts = []
  if (modifiers & MOD_META) parts.push("SUPER")
  if (modifiers & MOD_CTRL) parts.push("CTRL")
  if (modifiers & MOD_ALT) parts.push("ALT")
  if (modifiers & MOD_SHIFT) parts.push("SHIFT")
  if (parts.length === 0) return ""
  parts.push(name)
  return parts.join(" + ")
}

// Must match the validation in bin/apply-binding.sh.
function sanitizeShortcut(value) {
  var text = String(value || "").trim()
  if (text === "") return ""
  return /^[A-Za-z0-9_]+( \+ [A-Za-z0-9_]+)*$/.test(text) ? text : ""
}

function clampInt(value, limit) {
  var n = parseInt(value, 10)
  if (isNaN(n)) return limit.def
  return Math.max(limit.min, Math.min(limit.max, n))
}

// Never throws: a malformed or missing file yields defaults, so a bad hand
// edit degrades to "no hot corners" instead of taking the shell down.
function parse(text) {
  var cfg = defaults()
  var raw = null
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return cfg
  }
  if (!raw || typeof raw !== "object") return cfg

  cfg.triggerSize = clampInt(raw.triggerSize, LIMITS.triggerSize)
  cfg.dwellMs = clampInt(raw.dwellMs, LIMITS.dwellMs)
  cfg.cooldownMs = clampInt(raw.cooldownMs, LIMITS.cooldownMs)
  cfg.shortcut = sanitizeShortcut(raw.shortcut)
  // Opt-in: arming needs two extra Hyprland binds, so it stays off until asked.
  cfg.requireSuper = raw.requireSuper === true
  // Default-on: these correct annoyances rather than change what a corner does.
  cfg.suppressFullscreen = raw.suppressFullscreen !== false
  cfg.glow = raw.glow !== false

  var corners = raw.corners && typeof raw.corners === "object" ? raw.corners : {}
  for (var i = 0; i < CORNERS.length; i++) {
    var key = CORNERS[i]
    var entry = corners[key]
    var action = ""
    if (typeof entry === "string") action = entry
    else if (entry && typeof entry.action === "string") action = entry.action
    // Migrate the first version of the Stay awake preset to its enter/leave
    // behavior without requiring users to reconfigure their corner.
    if (action.trim() === "omarchy toggle idle stay-awake") action = STAY_AWAKE
    cfg.corners[key] = { action: action.trim() }
  }
  return cfg
}

function serialize(cfg) {
  return JSON.stringify(cfg, null, 2) + "\n"
}

function isPreset(action) {
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].value !== CUSTOM && PRESETS[i].value === action) return true
  }
  return false
}

// Which dropdown entry represents this command: itself when it is a preset,
// otherwise the custom escape hatch.
function presetFor(action) {
  return isPreset(action) ? action : CUSTOM
}

function clone(cfg) {
  return JSON.parse(JSON.stringify(cfg))
}
