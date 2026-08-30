import QtQuick
import Quickshell
import qs.Commons
// This file is itself called BarWidget.qml and `import "."` makes the plugin
// directory a module, so the shell's BarWidget has to be namespaced or the
// type would resolve to this file.
import qs.Ui as Ui
import "."

Ui.BarWidget {
  id: root
  moduleName: "io.github.weedwhitesandwine.ripcord"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  // Nerd Font glyphs rather than emoji, so they take the theme's bar
  // foreground like every other icon up there. An emoji would render as a
  // colour bitmap and ignore the theme entirely.
  //
  // Both sit in the BMP, so each is a single \u escape - anything above it
  // would need a surrogate pair.
  readonly property string glyphArmed: ""      // fa-lock
  readonly property string glyphDisarmed: ""   // fa-unlock

  // The icon is the feature, not decoration: for a trap that only matters when
  // it is set, being able to see at a glance whether it is armed is the point
  // of taking up a slot in the bar.
  readonly property string glyph: RipcordState.armed
    ? root.glyphArmed : root.glyphDisarmed

  readonly property string tooltip: {
    var parts = ["Ripcord — " + RipcordState.statusText]
    if (RipcordState.paired) {
      parts.push("Drive: " + (RipcordState.pairedLabel.length > 0
        ? RipcordState.pairedLabel : RipcordState.pairedUuid))
    }
    if (!RipcordState.watcherUp) parts.push("watcher down")
    return parts.join(" · ")
  }

  // Urgent while armed for real, so the bar distinguishes a trap that will
  // lock the machine from one that is only rehearsing. Also urgent when armed
  // with the watcher down, because that combination is a false sense of safety.
  readonly property bool alert: (RipcordState.armed && !RipcordState.rehearsal)
    || (RipcordState.armed && !RipcordState.watcherUp)

  // Red while the trap is live, amber while it is only
  // rehearsing, and the ordinary bar foreground when it is off. A padlock that
  // changes shape *and* colour is readable out of the corner of an eye.
  readonly property color stateColor: RipcordState.armed
    ? (RipcordState.rehearsal ? RipcordState.holdColor : RipcordState.liveColor)
    : (root.bar ? root.bar.barForeground : Color.foreground)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: root.tooltip
    active: root.alert
    // Red while the trap is live, amber while it is only
    // rehearsing, and the ordinary bar foreground when it is off. A padlock
    // that changes shape *and* colour is readable out of the corner of an eye.
    // Both, because WidgetButton uses activeColor in place of foreground
    // whenever it is active — setting only one leaves the armed icon the
    // theme's urgent colour instead of the one chosen here.
    foreground: root.stateColor
    activeColor: root.stateColor
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function (b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}
