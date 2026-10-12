import QtQuick
import qs.Commons

// One rounded block of the Control Center. A light wash of the text colour
// over the glass card, so the card's own blur still shows through.
Rectangle {
  property color fg: Color.foreground
  property bool hot: false
  property bool current: false

  radius: Style.cornerRadius
  color: current ? Util.alpha(Color.accent, 0.20) : Util.alpha(fg, hot ? 0.12 : 0.07)
  border.width: 1
  border.color: Util.alpha(fg, 0.10)

  Behavior on color { ColorAnimation { duration: 110 } }
}
