import QtQuick

// The diagonal hazard bar that runs across the top of the status block while
// the trap is live. Drawn rather than tiled from an image so it takes whatever
// colour it is given and costs nothing to ship.
//
// It animates by sliding a band that is drawn wider than the item and clipped,
// so the stripes appear to travel without anything being redrawn.
Item {
  id: root

  property color stripe: "#ff4d4d"
  property bool running: false
  property real stripeWidth: 10

  clip: true

  Row {
    id: band
    height: parent.height
    // Two full sets of stripes: the slide resets after one set has passed, so
    // the second set is already in place and the loop is seamless.
    x: 0
    spacing: 0

    Repeater {
      model: Math.ceil((root.width * 2) / (root.stripeWidth * 2)) + 2

      Item {
        width: root.stripeWidth * 2
        height: band.height

        Rectangle {
          width: root.stripeWidth
          height: parent.height * 2
          y: -parent.height / 2
          color: root.stripe
          opacity: 0.55
          rotation: 30
          antialiasing: true
        }
      }
    }
  }

  NumberAnimation {
    target: band
    property: "x"
    from: -root.stripeWidth * 2
    to: 0
    duration: 900
    loops: Animation.Infinite
    running: root.running && root.visible
  }
}
