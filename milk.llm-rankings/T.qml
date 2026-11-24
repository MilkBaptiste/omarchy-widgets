import QtQuick
import qs.Commons

// Text that follows the comfort settings (readable font, text size, spacing).
// `ui` is the widget root; it needs: barForeground, zoom, readable, readFamily.
Text {
  property var ui: null
  property real sz: Style.font.body
  color: ui ? ui.barForeground : Color.foreground
  textFormat: Text.PlainText
  font.family: ui && ui.readable ? ui.readFamily : Style.font.family
  font.pixelSize: sz * (ui ? ui.zoom : 1)
  font.letterSpacing: ui && ui.readable ? 0.7 : 0
  font.wordSpacing: ui && ui.readable ? 3 : 0
  lineHeight: ui && ui.readable ? 1.25 : 1.0
}
