import QtQuick
import QtQuick.Effects
import qs.Commons

// The round icon button of a Control Center row: filled with the accent
// colour while its subject is on, a faint disc while it is off.
Rectangle {
  id: root

  property bool on: false
  property string glyph: ""
  // An image to show in place of the glyph, tinted like one.
  property url icon: ""
  property color fg: Color.foreground
  property string family: Style.fontFamily
  property int size: Style.space(30)
  // Off for a disc that only shows state, with the click owned elsewhere.
  property bool interactive: true

  signal clicked()

  readonly property alias containsMouse: mouse.containsMouse

  width: size
  height: size
  radius: Style.cornerRadius > 0 ? size / 2 : 0
  color: on ? Color.accent : Util.alpha(fg, mouse.containsMouse ? 0.24 : 0.14)
  scale: mouse.pressed ? 0.92 : 1.0

  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

  Image {
    id: picture
    anchors.centerIn: parent
    width: Math.round(root.size * 0.56)
    height: width
    source: root.icon
    sourceSize.width: width * 2
    sourceSize.height: height * 2
    fillMode: Image.PreserveAspectFit
    visible: false
    layer.enabled: true
  }
  MultiEffect {
    anchors.fill: picture
    source: picture
    visible: root.icon != ""
    colorization: 1.0
    colorizationColor: root.on ? Color.background : root.fg
  }

  Text {
    anchors.centerIn: parent
    visible: root.icon == ""
    text: root.glyph
    color: root.on ? Color.background : root.fg
    font.family: root.family
    font.pixelSize: Math.round(root.size * 0.52)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
