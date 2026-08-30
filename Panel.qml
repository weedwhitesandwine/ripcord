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
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: RipcordState.statusText
                color: RipcordState.armed && !RipcordState.rehearsal
                  ? Color.urgent : root.barForeground
                font.bold: true
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
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
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.lastEvent.length > 0
                text: RipcordState.lastEvent
                color: root.barForeground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // --------------------------------------------- arming

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "THE TRAP"; foreground: root.barForeground }

              Ui.Button {
                width: parent.width
                text: RipcordState.armed ? "Disarm" : "Arm"
                enabled: RipcordState.armed || RipcordState.canArm()
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
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
                color: RipcordState.rehearsal ? root.barForeground : Color.urgent
                opacity: RipcordState.rehearsal ? 0.7 : 1.0
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.armed
                text: "Disarm before unplugging the drive on purpose."
                color: root.barForeground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
                onClicked: RipcordState.unpair()
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: RipcordState.drives.length > 0
                  ? "Removable drives attached now — choose one to pair:"
                  : "No removable drives attached. Plug one in to pair it."
                color: root.barForeground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: RipcordState.drives

                Ui.Button {
                  required property var modelData
                  width: mainColumn.width
                  text: (modelData.label && modelData.label.length > 0)
                    ? modelData.label
                    : modelData.uuid
                  enabled: modelData.uuid !== RipcordState.pairedUuid
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
                text: "Sleeping is off until you turn it on. Locking alone leaves the machine awake behind a password prompt; sleeping cuts power to everything but memory, and the lock screen is waiting when it wakes."
                color: root.barForeground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
                text: "While this is on, pulling the drive sends a notification saying what would have happened and nothing else. Leave it on until you have watched it fire once."
                color: root.barForeground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
