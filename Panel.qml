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
  // True only while re-choosing a drive that is already paired. Reset on open
  // so the panel never comes back mid-task from a session you have forgotten.
  property bool pickingDrive: false

  function open() {
    root.settingsOpen = false
    root.pickingDrive = false
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // Our own surface means our own text colours; the bar's foreground is tuned
  // for the bar's background, which is no longer what is behind this.
  readonly property color textColor: RipcordState.textColor
  readonly property color mutedColor: RipcordState.mutedTextColor

  readonly property string pairedName: RipcordState.pairedLabel.length > 0
    ? RipcordState.pairedLabel
    : "paired drive"

  // Drives are sized in the units printed on the box, so GB not GiB.
  function humanSize(bytes) {
    if (!bytes || bytes <= 0) return ""
    var gb = bytes / 1e9
    if (gb >= 10) return Math.round(gb) + " GB"
    if (gb >= 1) return gb.toFixed(1) + " GB"
    return Math.round(bytes / 1e6) + " MB"
  }

  // What to call a drive in the list: the volume name if it has one, since
  // that is what people recognise, and the hardware name when it does not.
  function driveTitle(drive) {
    if (!drive) return ""
    if (drive.label && drive.label.length > 0) return drive.label
    return drive.name && drive.name.length > 0 ? drive.name : drive.device
  }

  function driveSubtitle(drive) {
    if (!drive) return ""
    var parts = []
    if (drive.name && drive.name.length > 0) parts.push(drive.name)
    var size = root.humanSize(drive.size)
    if (size.length > 0) parts.push(size)
    return parts.join(" · ")
  }

  // Owned by RipcordState so the bar icon and this panel always agree, and so
  // the light-background variants are chosen in one place.
  readonly property color liveColor: RipcordState.liveColor
  readonly property color goColor: RipcordState.goColor
  readonly property color holdColor: RipcordState.holdColor

  readonly property color statusColor: {
    if (!RipcordState.paired) return root.textColor
    if (RipcordState.awaitingReinsert) return root.liveColor
    if (!RipcordState.armed) return root.textColor
    return RipcordState.rehearsal ? root.holdColor : root.liveColor
  }

  readonly property string statusCaps: RipcordState.statusText.toUpperCase()


  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Sized to what is actually in it rather than a fixed guess, which left
    // two-thirds of the panel empty once the pairing collapsed to one line.
    // fittedContentHeight still clamps it to the space on screen.
    contentHeight: panel.fittedContentHeight(
      headerRow.height + Style.spacing.lg
      + (root.settingsOpen ? settingsColumn.implicitHeight : mainColumn.implicitHeight)
      + Style.spacing.md)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Item {
        anchors.fill: parent

        // Ripcord's own surface, painted over the shell's popup background.
        // The negative margin covers the card's padding, which would otherwise
        // leave a ring of theme colour around the edge.
        Rectangle {
          anchors.fill: parent
          anchors.margins: -panel.padding
          radius: Style.cornerRadius
          color: RipcordState.surfaceColor
          z: -1

          Behavior on color { ColorAnimation { duration: 160 } }
        }

        // ----------------------------------------------------- header

        Row {
          id: headerRow
          width: parent.width
          height: Math.max(titleText.implicitHeight,
                          Math.max(gearButton.implicitHeight, modeButton.implicitHeight))
          spacing: Style.spacing.sm

          Text {
            id: titleText
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Ripcord"
            color: root.textColor
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
                             - modeButton.width - Style.spacing.sm
                             - (warnText.visible ? warnText.width + Style.spacing.sm : 0)
                             - Style.spacing.sm)
            height: 1
          }

          Ui.PanelActionButton {
            id: modeButton
            anchors.verticalCenter: parent.verticalCenter
            // Nerd Font glyphs rather than emoji, so they take the colour they
            // are given instead of rendering as colour bitmaps.
            // Written as escapes, not literal glyphs: a pasted Nerd Font
            // character does not survive every tool it passes through, and an
            // empty iconText renders as an invisible button rather than an
            // error. Both codepoints are in the BMP, so one \u each, and both
            // are present in JetBrains Mono Nerd Font (verified, not assumed).
            iconText: RipcordState.lightMode ? "\uF186" : "\uF185"
            tooltipText: RipcordState.lightMode
              ? "Switch to dark" : "Switch to light"
            foreground: root.textColor
            onClicked: RipcordState.toggleAppearance()
          }

          Ui.PanelActionButton {
            id: gearButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "✕" : "󰒓"
            tooltipText: root.settingsOpen ? "Back" : "Settings"
            foreground: root.textColor
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

              // The whole state of the thing in one block: hazard bar, lamp,
              // the word, and the two facts that qualify it. Bordered and
              // washed in the state colour so a glance is enough.
              Rectangle {
                id: statusBlock
                width: parent.width
                implicitHeight: statusInner.implicitHeight + Style.spacing.lg * 2
                                + stripes.height
                radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                color: Qt.rgba(root.statusColor.r, root.statusColor.g,
                               root.statusColor.b, 0.10)
                border.color: root.statusColor
                border.width: Math.max(1, Style.space(2))
                clip: true

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                HazardStripes {
                  id: stripes
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: parent.border.width
                  height: RipcordState.armed || RipcordState.awaitingReinsert
                    ? Style.space(8) : 0
                  stripe: root.statusColor
                  stripeWidth: Style.space(9)
                  running: RipcordState.armed || RipcordState.awaitingReinsert
                  visible: height > 0

                  Behavior on height { NumberAnimation { duration: 180 } }
                }

                Column {
                  id: statusInner
                  anchors.top: stripes.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.spacing.lg
                  spacing: Style.spacing.sm

                  Row {
                    width: parent.width
                    spacing: Style.spacing.md

                    // A lamp beside the readout, because a colour word alone
                    // is easy to skim past. It breathes only while the trap is
                    // set, so movement always means something.
                    Rectangle {
                      id: lamp
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(12)
                      height: width
                      radius: width / 2
                      color: root.statusColor

                      SequentialAnimation on opacity {
                        running: RipcordState.armed || RipcordState.awaitingReinsert
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.2; duration: 650; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - lamp.width - Style.spacing.md
                      elide: Text.ElideRight
                      text: root.statusCaps
                      color: root.statusColor
                      font.bold: true
                      font.letterSpacing: 2.0
                      font.family: root.fontFamily
                      // Deliberately the largest thing in the panel. Derived
                      // from the theme's scale rather than a fixed pixel size,
                      // so it still grows with the user's font settings.
                      font.pixelSize: Math.round(Style.font.title * 1.4)
                    }
                  }

                  // A two-column readout under the headline. Fixed-width
                  // labels so the values line up like an instrument panel.
                  Repeater {
                    // Only rows that carry something. With nothing paired the
                    // three of them read "none paired / — / lock", which is
                    // three lines saying what the headline already said.
                    // LINK earns its place only when the answer is a problem.
                    model: {
                      if (!RipcordState.paired) return []
                      var rows = [{ k: "DRIVE", v: root.pairedName }]
                      if (!RipcordState.pairedPresent)
                        rows.push({ k: "LINK", v: "NOT CONNECTED", alert: true })
                      rows.push({ k: "ON PULL", v: RipcordState.rehearsal
                          ? "rehearse only"
                          : (RipcordState.lockOnPull && RipcordState.suspendOnPull
                             ? "lock + sleep"
                             : RipcordState.suspendOnPull ? "sleep"
                             : RipcordState.lockOnPull ? "lock" : "nothing") })
                      return rows
                    }

                    Row {
                      required property var modelData
                      width: statusInner.width
                      spacing: Style.spacing.md

                      Text {
                        textFormat: Text.PlainText
                        width: Style.space(64)
                        text: modelData.k
                        color: root.mutedColor
                        font.letterSpacing: 1.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width - Style.space(64) - Style.spacing.md
                        elide: Text.ElideRight
                        text: modelData.v
                        color: modelData.alert === true
                          ? root.liveColor : root.textColor
                        font.bold: true
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: RipcordState.lastEvent.length > 0
                         && !RipcordState.armed
                text: RipcordState.lastEvent
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // ----------------------------------- pair, then arm
            //
            // One region, two states. Pairing is sequence-first - it has to
            // happen before arming - but arming is frequency-first: a drive is
            // paired once and armed every day after. A fixed order can serve
            // one or the other, so this serves whichever applies right now,
            // and never shows a control that cannot be used yet.

            Column {
              id: trapSection
              width: parent.width
              spacing: Style.spacing.md

              readonly property bool choosing: !RipcordState.paired || root.pickingDrive

              Ui.PanelSectionHeader {
                text: trapSection.choosing ? "CHOOSE YOUR KEY" : "THE TRAP"
                foreground: root.textColor
              }

              // ----------------------------------------- the trap

              HazardButton {
                width: parent.width
                height: Style.space(58)
                visible: !trapSection.choosing
                fontSize: Math.round(Style.font.title * 1.3)
                text: RipcordState.armed ? "STAND DOWN" : "ARM"
                // Green to engage, red to abort.
                tint: RipcordState.armed ? root.liveColor : root.goColor
                fontFamily: root.fontFamily
                // The glow runs while it is live, so the button itself is part
                // of the warning rather than just the thing that caused it.
                pulsing: RipcordState.armed && !RipcordState.rehearsal
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
                visible: !trapSection.choosing && !RipcordState.armed
                         && !RipcordState.canArm()
                text: "Plug the paired drive in before arming."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !trapSection.choosing && RipcordState.armed
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
                font.bold: !RipcordState.rehearsal
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !trapSection.choosing && RipcordState.armed
                text: "Disarm before unplugging if you intentionally want to remove the USB stick."
                color: root.mutedColor
                font.family: root.fontFamily
                // The two lines that say what will happen and how to avoid it
                // are the ones worth reading, so they are the ones set larger.
                font.pixelSize: Style.font.subtitle
              }

              // The paired drive, once it is settled, is one line rather than
              // a section: the status block above already names it, so a full
              // panel of it would be repeating what has just been read.
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                visible: !trapSection.choosing

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - changeButton.width - unpairButton.width
                         - Style.spacing.sm * 2
                  elide: Text.ElideRight
                  text: "Paired: " + root.pairedName
                  color: root.mutedColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Ui.Button {
                  id: changeButton
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Change"
                  bordered: true
                  foreground: root.textColor
                  fontSize: Style.font.bodySmall
                  onClicked: root.pickingDrive = true
                }

                Ui.Button {
                  id: unpairButton
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Unpair"
                  bordered: true
                  foreground: root.textColor
                  fontSize: Style.font.bodySmall
                  onClicked: {
                    RipcordState.unpair()
                    root.pickingDrive = false
                  }
                }
              }

              // -------------------------------------- choosing one

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                // Only speaks when there is nothing to click. With drives on
                // screen the rows are the instruction.
                visible: trapSection.choosing && RipcordState.drives.length === 0
                text: "Plug a USB drive in."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }

              Repeater {
                model: (!RipcordState.paired || root.pickingDrive)
                  ? RipcordState.drives : []

                // One row per physical drive, with the hardware name and size
                // underneath so a stick is identifiable even when its volume
                // name is unhelpful or missing.
                Rectangle {
                  id: driveRow
                  required property var modelData
                  readonly property bool isPaired:
                    modelData.id === RipcordState.pairedId

                  width: mainColumn.width
                  implicitHeight: driveText.implicitHeight + Style.spacing.lg * 2
                  radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                  color: driveMouse.containsMouse && !driveRow.isPaired
                    ? Qt.rgba(root.goColor.r, root.goColor.g, root.goColor.b, 0.12)
                    : "transparent"
                  border.color: root.goColor
                  border.width: Math.max(1, Style.space(2))

                  Behavior on color { ColorAnimation { duration: 120 } }

                  Text {
                    id: pairVerb
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    text: driveRow.isPaired ? "PAIRED" : "PAIR"
                    color: root.goColor
                    font.bold: true
                    font.letterSpacing: 1.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Column {
                    id: driveText
                    anchors.left: parent.left
                    anchors.right: pairVerb.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.spacing.md
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: root.driveTitle(driveRow.modelData)
                      color: driveRow.isPaired ? root.goColor : root.textColor
                      font.bold: true
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      visible: text.length > 0
                      text: {
                        var sub = root.driveSubtitle(driveRow.modelData)
                        return driveRow.isPaired ? (sub + "  ·  PAIRED") : sub
                      }
                      color: driveRow.isPaired ? root.goColor : root.mutedColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  MouseArea {
                    id: driveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !driveRow.isPaired
                    cursorShape: driveRow.isPaired
                      ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                      RipcordState.pair(driveRow.modelData.id,
                                        root.driveTitle(driveRow.modelData))
                      root.pickingDrive = false
                    }
                  }
                }
              }

              // Only offered while changing an existing pairing: with nothing
              // paired there is nothing to go back to.
              Ui.Button {
                width: parent.width
                visible: root.pickingDrive && RipcordState.paired
                text: "Cancel"
                bordered: true
                foreground: root.textColor
                fontSize: Style.font.bodySmall
                onClicked: root.pickingDrive = false
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

              Ui.PanelSectionHeader { text: "RESPONSE"; foreground: root.textColor }

              Ui.Toggle {
                width: parent.width
                label: "Lock the session"
                description: "Leaves the machine awake behind a password prompt"
                foreground: root.textColor
                checked: RipcordState.lockOnPull
                onClicked: RipcordState.lockOnPull = !RipcordState.lockOnPull
              }

              Ui.Toggle {
                width: parent.width
                label: "Put the machine to sleep"
                description: "Cuts power to everything but memory; the lock screen is waiting when it wakes"
                foreground: root.textColor
                checked: RipcordState.suspendOnPull
                onClicked: RipcordState.suspendOnPull = !RipcordState.suspendOnPull
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Sleeping stays off until you turn it on."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "REHEARSAL"; foreground: root.textColor }

              Ui.Toggle {
                width: parent.width
                label: "Rehearse instead of responding"
                description: "Pulling the drive only sends a notification"
                foreground: root.textColor
                checked: RipcordState.rehearsal
                onClicked: RipcordState.rehearsal = !RipcordState.rehearsal
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Leave this on until you have watched it fire once."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Ui.PanelSectionHeader { text: "LIMITS"; foreground: root.textColor }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Ripcord runs inside the desktop shell. If the shell stops, so does the watching — the bar icon is there so you can see whether it is armed. Arming is never restored automatically after a restart."
                color: root.mutedColor
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
