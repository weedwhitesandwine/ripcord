import QtQuick
import Quickshell
import qs.Commons
// Namespaced for the same reason as in BarWidget.qml: this file is called
// Panel.qml and `import "."` would otherwise make the shell's Panel ambiguous
// with this one.
import qs.Ui as Ui
import "."

Ui.Panel {
  id: root
  moduleName: "io.github.weedwhitesandwine.ripcord"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property bool settingsOpen: false

  function open() {
    root.settingsOpen = false
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property string pairedName: RipcordState.pairedLabel.length > 0
    ? RipcordState.pairedLabel
    : RipcordState.pairedUuid

  // Three states, three colours, taken from the active theme rather than
  // hardcoded so they still look native whatever is loaded.
  readonly property color liveColor: RipcordState.themeRed
  readonly property color goColor: RipcordState.themeGreen
  readonly property color holdColor: RipcordState.themeAmber

  readonly property color statusColor: {
    if (!RipcordState.paired) return root.barForeground
    if (RipcordState.awaitingReinsert) return root.liveColor
    if (!RipcordState.armed) return root.barForeground
    return RipcordState.rehearsal ? root.holdColor : root.liveColor
  }

  readonly property string statusCaps: RipcordState.statusText.toUpperCase()

  // Secondary text is the theme's own foreground rather than a dimmed version
  // of it: grey on a dark background is exactly what this should not do.
  readonly property real secondaryOpacity: 0.92

  // ---------------------------------------------------------------- view

  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Style.space(root.settingsOpen ? 400 : 520))

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Item {
        anchors.fill: parent

        // ----------------------------------------------------- header

        Row {
          id: headerRow
          width: parent.width
          height: Math.max(titleText.implicitHeight, gearButton.implicitHeight)
          spacing: Style.spacing.sm

          Text {
            id: titleText
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Ripcord"
            color: root.barForeground
            font.bold: true
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }

          Text {
            id: warnText
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: !RipcordState.watcherUp
            text: "watcher down"
            color: root.liveColor
            font.bold: true
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Item {
            width: Math.max(0, headerRow.width - titleText.width - gearButton.width
                             - (warnText.visible ? warnText.width + Style.spacing.sm : 0)
                             - Style.spacing.sm)
            height: 1
          }

          Ui.PanelActionButton {
            id: gearButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "✕" : "󰒓"
            tooltipText: root.settingsOpen ? "Back" : "Settings"
            foreground: root.barForeground
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }

        // ------------------------------------------------------- body

        Flickable {
          id: bodyFlick
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          contentWidth: width
          contentHeight: root.settingsOpen
            ? settingsColumn.implicitHeight
            : mainColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          // --------------------------------------------------- main

          Column {
            id: mainColumn
            visible: !root.settingsOpen
            width: bodyFlick.width
            spacing: Style.spacing.xl

            // ------------------------------------------- status

            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Ui.PanelSectionHeader { text: "STATUS"; foreground: root.barForeground }

              Row {
                width: parent.width
                spacing: Style.spacing.sm

                // A lamp beside the readout, because a colour word alone is
                // easy to skim past. It breathes only when the trap is live,
                // so movement means something rather than being decoration.
                Rectangle {
                  id: lamp
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(10)
                  height: width
                  radius: width / 2
                  color: root.statusColor
                  visible: RipcordState.paired

                  SequentialAnimation on opacity {
                    running: RipcordState.armed || RipcordState.awaitingReinsert
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                  }
                  // Left at full strength when nothing is animating, or a
                  // paused animation would strand it half faded.
                  onVisibleChanged: if (!RipcordState.armed) opacity = 1.0
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - (lamp.visible ? lamp.width + Style.spacing.sm : 0)
                  wrapMode: Text.WordWrap
                  text: root.statusCaps
                  color: root.statusColor
                  font.bold: true
                  font.letterSpacing: 1.2
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.paired
                text: RipcordState.pairedPresent
                  ? ("Paired drive is connected — " + root.pairedName)
                  : ("Paired drive not connected — " + root.pairedName)
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.lastEvent.length > 0
                text: RipcordState.lastEvent
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // --------------------------------------------- arming

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "THE TRAP"; foreground: root.barForeground }

              Ui.Button {
                width: parent.width
                text: RipcordState.armed ? "STAND DOWN" : "ARM"
                bordered: true
                // Green to engage, red to abort — and the colour comes from
                // the theme, so it is this theme's green rather than a green
                // that fights it.
                foreground: RipcordState.armed ? root.liveColor : root.goColor
                accent: RipcordState.armed ? root.liveColor : root.goColor
                fontSize: Style.font.title
                enabled: RipcordState.armed || RipcordState.canArm()
                opacity: enabled ? 1.0 : 0.5
                onClicked: {
                  if (RipcordState.armed) RipcordState.disarm()
                  else RipcordState.arm()
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !RipcordState.armed && !RipcordState.canArm()
                text: !RipcordState.paired
                  ? "Pair a drive below before arming."
                  : "Plug the paired drive in before arming."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.armed
                text: RipcordState.rehearsal
                  ? "Rehearsal is on: pulling the drive sends a notification and does nothing else."
                  : ("Pulling the drive will "
                     + (RipcordState.lockOnPull && RipcordState.suspendOnPull
                        ? "lock the session and put the machine to sleep."
                        : RipcordState.suspendOnPull
                          ? "put the machine to sleep."
                          : RipcordState.lockOnPull
                            ? "lock the session."
                            : "do nothing — no response is enabled."))
                color: RipcordState.rehearsal ? root.holdColor : root.liveColor
                opacity: 1.0
                font.bold: !RipcordState.rehearsal
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.armed
                text: "Disarm before unplugging the drive on purpose."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // -------------------------------------------- pairing

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "PAIRED DRIVE"; foreground: root.barForeground }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.paired
                text: root.pairedName
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Ui.Button {
                width: parent.width
                visible: RipcordState.paired
                text: "Unpair"
                bordered: true
                foreground: root.barForeground
                onClicked: RipcordState.unpair()
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                // One physical stick can carry several filesystems, and each
                // is listed separately because each has its own identifier.
                // Pairing any one of them is enough: they all disappear
                // together when the drive is pulled.
                text: RipcordState.drives.length > 0
                  ? "Filesystems on drives you can unplug — choose one to pair:"
                  : "No removable drives attached. Plug one in to pair it."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: RipcordState.drives

                Ui.Button {
                  required property var modelData
                  width: mainColumn.width
                  text: (modelData.label && modelData.label.length > 0)
                    ? modelData.label
                    : modelData.uuid
                  // The tooltip is rendered as rich text by the shell, so the
                  // label - which is whatever somebody named their drive -
                  // has its angle brackets taken out before it goes in.
                  tooltipText: (modelData.device + " · " + modelData.uuid)
                    .replace(/[<>]/g, "")
                  bordered: true
                  foreground: root.barForeground
                  enabled: modelData.uuid !== RipcordState.pairedUuid
                  opacity: enabled ? 1.0 : 0.45
                  onClicked: RipcordState.pair(modelData.uuid, modelData.label)
                }
              }
            }
          }

          // ----------------------------------------------- settings

          Column {
            id: settingsColumn
            visible: root.settingsOpen
            width: bodyFlick.width
            spacing: Style.spacing.xl

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "RESPONSE"; foreground: root.barForeground }

              Ui.Toggle {
                width: parent.width
                label: "Lock the session"
                description: "Leaves the machine awake behind a password prompt"
                foreground: root.barForeground
                checked: RipcordState.lockOnPull
                onClicked: RipcordState.lockOnPull = !RipcordState.lockOnPull
              }

              Ui.Toggle {
                width: parent.width
                label: "Put the machine to sleep"
                description: "Cuts power to everything but memory; the lock screen is waiting when it wakes"
                foreground: root.barForeground
                checked: RipcordState.suspendOnPull
                onClicked: RipcordState.suspendOnPull = !RipcordState.suspendOnPull
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Sleeping stays off until you turn it on."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "REHEARSAL"; foreground: root.barForeground }

              Ui.Toggle {
                width: parent.width
                label: "Rehearse instead of responding"
                description: "Pulling the drive only sends a notification"
                foreground: root.barForeground
                checked: RipcordState.rehearsal
                onClicked: RipcordState.rehearsal = !RipcordState.rehearsal
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Leave this on until you have watched it fire once."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "LIMITS"; foreground: root.barForeground }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Ripcord runs inside the desktop shell. If the shell stops, so does the watching — the bar icon is there so you can see whether it is armed. Arming is never restored automatically after a restart."
                color: root.barForeground
                opacity: root.secondaryOpacity
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
