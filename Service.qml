import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Config.js" as Config

// Hot corner triggers.
//
// One transparent layer-shell surface per screen, with its input region masked
// down to just the enabled corner squares. Everything else stays click-through,
// including the dwell glow, which is drawn outside the mask. Configuration
// lives in ~/.config/omarchy/hotcorners.json and is watched, so edits from the
// settings GUI or a text editor apply immediately.
Item {
  id: root

  readonly property string configPath: Quickshell.env("HOME") + Config.PATH_SUFFIX
  property var config: Config.defaults()
  property bool seeded: false

  property double lastFiredAt: 0

  // ------------------------------------------------------- suppression

  // Tracked from Hyprland's event stream rather than polled.
  property bool fullscreen: false

  // Set by the Hyprland binds that apply-binding.sh installs when
  // requireSuper is on. Meaningless while it is off.
  property bool superHeld: false

  readonly property bool suppressed:
    (root.config.suppressFullscreen && root.fullscreen)
    || (root.config.requireSuper && !root.superHeld)

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "fullscreen") {
      root.fullscreen = String(event.data || "").trim() === "1"
    } else if (name === "closewindow" || name === "closelayer") {
      // A fullscreen window closing does not always emit fullscreen>>0.
      fullscreenProbe.running = true
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  // Seeds the initial state, and re-checks after a window closes.
  Process {
    id: fullscreenProbe
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var w = JSON.parse(text)
          root.fullscreen = Number(w.fullscreen || 0) > 0
        } catch (e) {
          root.fullscreen = false
        }
      }
    }
  }

  Component.onCompleted: {
    fullscreenProbe.running = true
    Quickshell.execDetached([
      Quickshell.env("HOME") + "/.config/omarchy/plugins/abdul.hotcorners/bin/stay-awake.sh",
      "recover"
    ])
  }

  // ---------------------------------------------------------- actions

  function actionFor(corner) {
    var entry = root.config.corners[corner]
    return entry ? entry.action : ""
  }

  function fire(action) {
    if (!action) return
    if (action === Config.STAY_AWAKE) return
    var now = Date.now()
    if (now - root.lastFiredAt < root.config.cooldownMs) return
    root.lastFiredAt = now
    Quickshell.execDetached(["bash", "-lc", action])
  }

  function setCornerStayAwake(entering) {
    var script = Quickshell.env("HOME") + "/.config/omarchy/plugins/abdul.hotcorners/bin/stay-awake.sh"
    Quickshell.execDetached([script, entering ? "enter" : "leave"])
  }

  // Write the defaults out once so the file is there to hand-edit and the
  // shape is self-documenting. Only on a genuinely absent file.
  function seedConfig() {
    if (root.seeded) return
    root.seeded = true
    configFile.setText(Config.serialize(Config.defaults()))
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.seeded = true
      root.config = Config.parse(text())
    }
    onLoadFailed: {
      root.config = Config.defaults()
      root.seedConfig()
    }
    onFileChanged: reload()
  }

  IpcHandler {
    target: "hotcorners"

    // Run a corner's action now, ignoring dwell, cooldown, and suppression.
    function trigger(corner: string): string {
      var action = root.actionFor(corner)
      if (!action) return corner + " is not configured"
      root.lastFiredAt = 0
      root.fire(action)
      return "ok"
    }

    // Called by the Hyprland Super press/release binds when requireSuper is on.
    function arm(state: string): string {
      root.superHeld = (state === "1" || state === "true" || state === "on")
      return root.superHeld ? "armed" : "disarmed"
    }

    // Configured actions, timings, and live trigger rects, for verifying setup.
    function status(): string {
      var out = []
      for (var i = 0; i < Config.CORNERS.length; i++) {
        var c = Config.CORNERS[i]
        out.push(c + "=" + (root.actionFor(c) || "-"))
      }
      var line = out.join(" ")
      line += " | size=" + root.config.triggerSize
        + " dwell=" + root.config.dwellMs
        + " cooldown=" + root.config.cooldownMs
        + " | requireSuper=" + root.config.requireSuper
        + " superHeld=" + root.superHeld
        + " suppressFullscreen=" + root.config.suppressFullscreen
        + " fullscreen=" + root.fullscreen
        + " suppressed=" + root.suppressed
      for (var s = 0; s < panels.instances.length; s++) {
        var p = panels.instances[s]
        line += " | " + p.screen.name + " " + p.width + "x" + p.height + " " + p.rects
      }
      return line
    }

    function configPath(): string { return root.configPath }
  }

  component Corner: Item {
    id: corner
    required property string action
    required property int ax   // -1 anchored left, 1 anchored right
    required property int ay   // -1 anchored top,  1 anchored bottom

    readonly property bool armed: action !== ""
    width: armed ? root.config.triggerSize : 0
    height: armed ? root.config.triggerSize : 0

    // 0 while idle, ramping to 1 over the dwell time. Drives both the glow
    // and the trigger, so what you see is exactly how close it is to firing.
    property real progress: 0
    property bool stayAwakeActive: false

    readonly property string rect: Math.round(x) + "," + Math.round(y) + " " + width + "x" + height

    NumberAnimation {
      id: dwell
      target: corner
      property: "progress"
      from: 0
      to: 1
      duration: Math.max(1, root.config.dwellMs)
      onFinished: {
        if (corner.action === Config.STAY_AWAKE) {
          root.setCornerStayAwake(true)
          corner.stayAwakeActive = true
        } else {
          root.fire(corner.action)
        }
      }
    }

    function cancel() {
      dwell.stop()
      corner.progress = 0
      if (corner.stayAwakeActive) {
        corner.stayAwakeActive = false
        root.setCornerStayAwake(false)
      }
    }

    // Suppression that arrives mid-dwell disarms the corner immediately.
    Connections {
      target: root
      function onSuppressedChanged() { if (root.suppressed) corner.cancel() }
    }

    // The glow lives outside the 4x4 input region, so it is drawn but never
    // clickable. Half of it sits off-screen, leaving a quarter-circle bloom
    // in the corner itself.
    Rectangle {
      id: glow
      visible: root.config.glow && corner.progress > 0
      width: Style.space(160) * corner.progress
      height: width
      radius: width / 2
      x: (corner.ax < 0 ? 0 : corner.width) - width / 2
      y: (corner.ay < 0 ? 0 : corner.height) - height / 2
      color: Color.accent
      opacity: 0.35 * corner.progress
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: {
        if (!corner.armed || root.suppressed) return
        dwell.restart()
      }
      onExited: corner.cancel()
    }
  }

  Variants {
    id: panels
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      readonly property string rects: "tl=" + tl.rect + " tr=" + tr.rect
        + " bl=" + bl.rect + " br=" + br.rect

      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-hotcorners"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Only the armed corner squares take pointer input; a disabled corner
      // collapses to 0x0 and drops out of the region entirely. The glow is
      // not listed here, so it never becomes clickable.
      mask: Region {
        Region { item: tl }
        Region { item: tr }
        Region { item: bl }
        Region { item: br }
      }

      Corner {
        id: tl
        action: root.actionFor("top-left"); ax: -1; ay: -1
        anchors { top: parent.top; left: parent.left }
      }
      Corner {
        id: tr
        action: root.actionFor("top-right"); ax: 1; ay: -1
        anchors { top: parent.top; right: parent.right }
      }
      Corner {
        id: bl
        action: root.actionFor("bottom-left"); ax: -1; ay: 1
        anchors { bottom: parent.bottom; left: parent.left }
      }
      Corner {
        id: br
        action: root.actionFor("bottom-right"); ax: 1; ay: 1
        anchors { bottom: parent.bottom; right: parent.right }
      }
    }
  }
}
