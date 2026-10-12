import QtQuick
import qs.Commons

// A connectivity row: round on/off button, then the subject's name over what
// it is connected to. The button switches; the rest of the row is `opened`.
Item {
  id: root

  property string title: ""
  property string status: ""
  property string glyph: ""
  property url icon: ""
  property bool on: false
  property bool current: false
  property bool chevron: true
  property color fg: Color.foreground
  property string family: Style.fontFamily

  signal toggled()
  signal opened()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.current ? Util.alpha(Color.accent, 0.22)
      : (rowMouse.containsMouse ? Util.alpha(root.fg, 0.10) : "transparent")
    Behavior on color { ColorAnimation { duration: 110 } }
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  RoundToggle {
    id: toggle
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    on: root.on
    glyph: root.glyph
    icon: root.icon
    fg: root.fg
    family: root.family
    onClicked: root.toggled()
  }

  Column {
    anchors.left: toggle.right
    anchors.leftMargin: Style.space(9)
    anchors.right: arrow.left
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.title
      color: root.fg
      elide: Text.ElideRight
      font.family: root.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }
    Text {
      width: parent.width
      text: root.status
      color: root.fg
      opacity: 0.65
      elide: Text.ElideRight
      font.family: root.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    id: arrow
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.chevron
    width: root.chevron ? implicitWidth : 0
    text: String.fromCodePoint(0xF0142)
    color: root.fg
    opacity: root.current || rowMouse.containsMouse ? 0.9 : 0.35
    font.family: root.family
    font.pixelSize: Style.font.body
  }
}
