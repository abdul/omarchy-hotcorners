import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Config.js" as Config

// Hot corner triggers.
//
// One transparent layer-shell surface per screen, with its input region masked
// down to just the enabled corner squares. Everything else stays click-through.
// Configuration lives in ~/.config/omarchy/hotcorners.json and is watched, so
// edits from the settings GUI or a text editor apply immediately.
Item {
  id: root

  readonly property string configPath: Quickshell.env("HOME") + Config.PATH_SUFFIX
  property var config: Config.defaults()
  property bool seeded: false

  property double lastFiredAt: 0

  function actionFor(corner) {
    var entry = root.config.corners[corner]
    return entry ? entry.action : ""
  }

  function fire(action) {
    if (!action) return
    var now = Date.now()
    if (now - root.lastFiredAt < root.config.cooldownMs) return
    root.lastFiredAt = now
    Quickshell.execDetached(["bash", "-lc", action])
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

    // Run a corner's action now, ignoring dwell and cooldown.
    function trigger(corner: string): string {
      var action = root.actionFor(corner)
      if (!action) return corner + " is not configured"
      root.lastFiredAt = 0
      root.fire(action)
      return "ok"
    }

    // Configured actions plus the live trigger rects, for verifying setup.
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

    readonly property bool armed: action !== ""
    width: armed ? root.config.triggerSize : 0
    height: armed ? root.config.triggerSize : 0

    readonly property string rect: Math.round(x) + "," + Math.round(y) + " " + width + "x" + height

    Timer {
      id: dwell
      interval: root.config.dwellMs
      onTriggered: root.fire(corner.action)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: if (corner.armed) dwell.restart()
      onExited: dwell.stop()
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
      // collapses to 0x0 and drops out of the region entirely.
      mask: Region {
        Region { item: tl }
        Region { item: tr }
        Region { item: bl }
        Region { item: br }
      }

      Corner {
        id: tl
        action: root.actionFor("top-left")
        anchors { top: parent.top; left: parent.left }
      }
      Corner {
        id: tr
        action: root.actionFor("top-right")
        anchors { top: parent.top; right: parent.right }
      }
      Corner {
        id: bl
        action: root.actionFor("bottom-left")
        anchors { bottom: parent.bottom; left: parent.left }
      }
      Corner {
        id: br
        action: root.actionFor("bottom-right")
        anchors { bottom: parent.bottom; right: parent.right }
      }
    }
  }
}
