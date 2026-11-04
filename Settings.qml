import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Config.js" as Config

// Settings GUI for the hot corners.
//
// Edits a working copy and only writes ~/.config/omarchy/hotcorners.json on
// Save; the service watches that file, so saving applies immediately without
// a shell restart.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var service: null
  property var manifest: null

  property bool opened: false
  property bool capturing: false
  property string selectedCorner: "top-left"
  property var working: Config.defaults()

  readonly property string configPath: Quickshell.env("HOME") + Config.PATH_SUFFIX

  // Shares the [menu] surface tokens, so themes that style the menu style
  // this too.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  function open(payloadJson) {
    root.loadFromDisk()
    root.selectedCorner = "top-left"
    root.syncControls()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Dropdown assigns its own `value` on selection and TextField drops its
  // binding the moment it is typed into, so neither can be driven
  // declaratively. Push the working state into them by hand instead.
  function syncControls() {
    var action = root.actionFor(root.selectedCorner)
    presetPicker.value = Config.presetFor(action)
    commandField.text = action
    sizeField.field.value = root.working.triggerSize
    dwellField.field.value = root.working.dwellMs
    cooldownField.field.value = root.working.cooldownMs
  }

  function selectCorner(corner) {
    root.selectedCorner = corner
    root.syncControls()
  }

  function commitCommand() {
    root.setAction(root.selectedCorner, commandField.text)
    presetPicker.value = Config.presetFor(commandField.text.trim())
  }

  function close() {
    root.capturing = false
    root.opened = false
  }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }

  function loadFromDisk() {
    configFile.reload()
    root.working = Config.parse(configFile.text())
  }

  function save() {
    var previous = Config.parse(configFile.text())
    configFile.setText(Config.serialize(root.working))
    // Only touch the user's Hyprland config when something that lives there
    // actually changed, so an ordinary Save never rewrites bindings.lua.
    if (root.working.shortcut !== previous.shortcut
        || root.working.requireSuper !== previous.requireSuper) {
      root.applyBindings(root.working.shortcut, root.working.requireSuper)
    }
    root.close()
  }

  function applyBindings(shortcut, requireSuper) {
    var dir = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    if (dir === "") {
      console.warn("hotcorners: no plugin source dir, cannot apply keybindings")
      return
    }
    Quickshell.execDetached(["bash", dir + "/bin/apply-binding.sh",
      String(shortcut || ""), requireSuper ? "super" : ""])
  }

  function setFlag(key, value) {
    var next = Config.clone(root.working)
    next[key] = value === true
    root.working = next
  }

  function setShortcut(value) {
    var next = Config.clone(root.working)
    next.shortcut = Config.sanitizeShortcut(value)
    root.working = next
  }

  function actionFor(corner) {
    var entry = root.working.corners[corner]
    return entry ? entry.action : ""
  }

  // Working config is a plain JS object, so reassign the whole thing to make
  // the change visible to bindings.
  function setAction(corner, action) {
    var next = Config.clone(root.working)
    next.corners[corner] = { action: String(action).trim() }
    root.working = next
  }

  function setNumber(key, value) {
    var next = Config.clone(root.working)
    next[key] = Config.clampInt(value, Config.LIMITS[key])
    root.working = next
  }

  function summaryFor(corner) {
    var action = root.actionFor(corner)
    if (!action) return "Nothing"
    for (var i = 0; i < Config.PRESETS.length; i++) {
      if (Config.PRESETS[i].value === action) return Config.PRESETS[i].label
    }
    return action
  }

  // blockAllReads makes reload()/text() synchronous, so open() sees what is
  // actually on disk rather than a stale cache. The file is tiny and only
  // read when the GUI opens, so blocking costs nothing.
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    blockAllReads: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
  }

  IpcHandler {
    target: "hotcorners-settings"
    function open(): string { root.open("{}"); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }

    // Set (or clear, with "") the keybinding without opening the GUI.
    function shortcut(combo: string): string {
      var clean = Config.sanitizeShortcut(combo)
      if (combo !== "" && clean === "") return "rejected malformed shortcut: " + combo
      var cfg = Config.parse(configFile.text())
      cfg.shortcut = clean
      configFile.setText(Config.serialize(cfg))
      if (root.opened) root.working = Config.clone(cfg)
      root.applyBindings(clean, cfg.requireSuper)
      return clean === "" ? "cleared" : clean
    }
  }

  // A corner tile in the screen diagram: click to select, shows what it does.
  component CornerTile: Rectangle {
    id: tile
    required property string corner
    required property int alignX   // -1 left, 1 right
    required property int alignY   // -1 top, 1 bottom

    readonly property bool selected: root.selectedCorner === tile.corner
    readonly property bool assigned: root.actionFor(tile.corner) !== ""

    width: Style.space(150)
    height: Style.space(52)
    radius: Style.cornerRadius
    color: tile.selected ? Util.alpha(root.accent, 0.18)
      : (hover.hovered ? Util.alpha(root.foreground, 0.08) : "transparent")
    border.width: Math.max(1, Style.space(2))
    border.color: tile.selected ? root.accent
      : (tile.assigned ? Util.alpha(root.foreground, 0.45) : Util.alpha(root.foreground, 0.18))

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.sm

      Text {
        text: Config.CORNER_LABELS[tile.corner]
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.summaryFor(tile.corner)
        color: tile.assigned ? root.foreground : Qt.darker(root.foreground, 1.8)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: root.selectCorner(tile.corner) }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-hotcorners-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }

      BorderSurface {
        id: card
        width: Math.min(Style.space(880), panel.width - Style.gapsOut * 2)
        height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset,
          panel.height - Style.gapsOut * 2)
        radius: Style.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        // Swallow clicks so they do not reach the close handler behind.
        MouseArea { anchors.fill: parent; onClicked: {} }

        // Takes every key while recording, so the combination being pressed
        // cannot also act on the controls underneath.
        Item {
          id: shortcutCatcher
          anchors.fill: parent
          z: 10
          enabled: root.capturing
          focus: root.capturing
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            event.accepted = true
            if (event.key === Qt.Key_Escape) { root.capturing = false; return }
            if (Config.isModifierKey(event.key)) return
            var combo = Config.shortcutFrom(event.modifiers, event.key)
            if (combo === "") return
            root.setShortcut(combo)
            root.capturing = false
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }

        Column {
          id: content
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: card.contentTopInset
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          spacing: Style.spacing.huge

          // ---------------------------------------------------- header
          Column {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              text: "Hot Corners"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "Rest the pointer in a corner of the screen to run a command."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ------------------------------------- diagram + corner editor
          Row {
            width: parent.width
            height: Style.space(300)
            spacing: Style.spacing.huge

            // A stand-in for the screen, with the four corners in place.
            Rectangle {
              id: diagram
              width: Math.round(parent.width * 0.52)
              height: parent.height
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.05)
              border.width: Math.max(1, Style.space(2))
              border.color: Util.alpha(root.foreground, 0.2)

              CornerTile {
                corner: "top-left"; alignX: -1; alignY: -1
                anchors { top: parent.top; left: parent.left; margins: Style.spacing.lg }
              }
              CornerTile {
                corner: "top-right"; alignX: 1; alignY: -1
                anchors { top: parent.top; right: parent.right; margins: Style.spacing.lg }
              }
              CornerTile {
                corner: "bottom-left"; alignX: -1; alignY: 1
                anchors { bottom: parent.bottom; left: parent.left; margins: Style.spacing.lg }
              }
              CornerTile {
                corner: "bottom-right"; alignX: 1; alignY: 1
                anchors { bottom: parent.bottom; right: parent.right; margins: Style.spacing.lg }
              }

              Text {
                anchors.centerIn: parent
                text: "your screen"
                color: Qt.darker(root.foreground, 2.0)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // ------------------------------------------- corner editor
            Column {
              width: parent.width - diagram.width - Style.spacing.huge
              spacing: Style.spacing.lg

              PanelSectionHeader {
                text: Config.CORNER_LABELS[root.selectedCorner]
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Dropdown {
                id: presetPicker
                width: parent.width
                label: "Action"
                fontFamily: root.fontFamily
                options: Config.PRESETS
                onChanged: function(v) {
                  if (v === Config.CUSTOM) {
                    // Keep whatever is already there and let them type.
                    Qt.callLater(function() { commandField.forceActiveFocus() })
                    return
                  }
                  root.setAction(root.selectedCorner, v)
                  commandField.text = v
                }
              }

              Column {
                width: parent.width
                spacing: Style.spacing.labelGap

                Text {
                  text: "Command"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                TextField {
                  id: commandField
                  width: parent.width
                  placeholderText: "Leave empty to disable this corner"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onEditingFinished: root.commitCommand()
                  onAccepted: root.commitCommand()
                }

                Text {
                  width: parent.width
                  text: "Runs through bash, so pipes and arguments work."
                  color: Qt.darker(root.foreground, 1.8)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          // --------------------------------------------------- timings
          Row {
            width: parent.width
            spacing: Style.spacing.huge

            NumberField {
              id: sizeField
              label: "Trigger size (px)"
              from: Config.LIMITS.triggerSize.min
              to: Config.LIMITS.triggerSize.max
              value: root.working.triggerSize
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.setNumber("triggerSize", v) }
            }
            NumberField {
              id: dwellField
              label: "Dwell (ms)"
              from: Config.LIMITS.dwellMs.min
              to: Config.LIMITS.dwellMs.max
              stepSize: 50
              value: root.working.dwellMs
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.setNumber("dwellMs", v) }
            }
            NumberField {
              id: cooldownField
              label: "Cooldown (ms)"
              from: Config.LIMITS.cooldownMs.min
              to: Config.LIMITS.cooldownMs.max
              stepSize: 100
              value: root.working.cooldownMs
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.setNumber("cooldownMs", v) }
            }
          }

          // -------------------------------------------------- shortcut
          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            Text {
              text: "Keyboard shortcut"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                id: captureButton
                bordered: true
                selected: root.capturing
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                text: root.capturing
                  ? "Press a combination\u2026"
                  : (root.working.shortcut !== "" ? root.working.shortcut : "Set a shortcut")
                onClicked: {
                  root.capturing = true
                  Qt.callLater(function() { shortcutCatcher.forceActiveFocus() })
                }
              }

              Button {
                text: "Clear"
                bordered: true
                visible: root.working.shortcut !== "" && !root.capturing
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.setShortcut("")
              }
            }

            Text {
              width: parent.width
              text: root.capturing
                ? "Esc cancels. A modifier is required, so ordinary typing keeps working."
                : "Opens this window. Saving writes it into ~/.config/hypr/bindings.lua."
              color: Qt.darker(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ------------------------------------------------- behaviour
          Column {
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              text: "Behaviour"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Hold Super to arm"
              description: "Corners only fire while Super is held, so dragging a window "
                + "to an edge cannot trip them. Adds two binds to bindings.lua."
              checked: root.working.requireSuper
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setFlag("requireSuper", !root.working.requireSuper)
            }

            Toggle {
              width: parent.width
              label: "Ignore fullscreen windows"
              description: "Do not fire while a window is fullscreen."
              checked: root.working.suppressFullscreen
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setFlag("suppressFullscreen", !root.working.suppressFullscreen)
            }

            Toggle {
              width: parent.width
              label: "Show the dwell glow"
              description: "An accent bloom grows in the corner while it arms."
              checked: root.working.glow
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setFlag("glow", !root.working.glow)
            }
          }

          // ---------------------------------------------------- footer
          Item {
            width: parent.width
            height: Style.spacing.controlHeight + Style.spacing.md

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.configPath.replace(Quickshell.env("HOME"), "~")
              color: Qt.darker(root.foreground, 2.0)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md

              Button {
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.close()
              }
              Button {
                text: "Save"
                bordered: true
                selected: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.save()
              }
            }
          }
        }
      }
    }
  }
}
