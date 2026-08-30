import QtQuick
import qs.Commons

// A control-panel button: heavy border, a faint wash of its own colour, and a
// glow that comes up under the cursor. Deliberately not the shell's Ui.Button
// - this plugin gets one bold look of its own rather than blending into the
// furniture, and the two buttons that matter here are the two that need to be
// unmistakable at a glance.
Item {
  id: root

  property string text: ""
  property color tint: "#7fe08a"
  property bool enabled: true
  property real fontSize: Style.font.title
  property string fontFamily: Style.font.family
  // Live buttons breathe; the ordinary ones sit still.
  property bool pulsing: false

  signal clicked()

  implicitHeight: Math.max(Style.space(38), label.implicitHeight + Style.spacing.md * 2)
  opacity: root.enabled ? 1.0 : 0.4

  Rectangle {
    id: body
    anchors.fill: parent
    radius: Style.cornerRadius > 0 ? Style.space(6) : 0
    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b,
                   mouse.containsMouse && root.enabled ? 0.22 : 0.10)
    border.color: root.tint
    border.width: Math.max(1, Style.space(2))

    Behavior on color { ColorAnimation { duration: 120 } }

    // The glow: a second rounded rect bleeding outward, faint and slow. It
    // only runs while the button is pulsing, so it reads as a state rather
    // than as decoration.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + Style.space(8)
      height: parent.height + Style.space(8)
      radius: parent.radius + Style.space(4)
      color: "transparent"
      border.color: root.tint
      border.width: Math.max(1, Style.space(2))
      visible: root.pulsing
      opacity: 0.0

      SequentialAnimation on opacity {
        running: root.pulsing
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 900; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      id: label
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.text
      color: root.tint
      font.bold: true
      font.letterSpacing: 2.5
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
