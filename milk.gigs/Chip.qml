import QtQuick
import qs.Commons
import qs.Commons as Commons

// Milk-style button: square, crisp, every colour/size from the shell's theme tokens.
//   idle     1px foreground border (Style.normalBorderAlpha)
//   hover    brighter border + hover fill
//   pressed  pressed fill
//   active   accent fill + 2px accent border + bold text (+ check mark if `check`)
// `ui` is the widget root; it needs: barForeground, zoom, readable, readFamily.
Rectangle {
  id: chip
  property var ui: null
  property string label: ""
  property bool active: false
  property bool check: false          // show a check mark when active so state is never colour-only
  property url icon: ""
  property real sz: Style.font.caption
  signal clicked()

  readonly property color fg: ui ? ui.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property real zoom: ui ? ui.zoom : 1

  implicitWidth: row.implicitWidth + Style.spacing.controlPaddingX * 2 * zoom
  implicitHeight: Style.spacing.controlHeight * zoom
  radius: Style.cornerRadius          // follows the theme (square when the theme says 0)
  antialiasing: false                 // keeps square edges pixel-sharp
  color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.30)
       : mouse.pressed ? Qt.rgba(fg.r, fg.g, fg.b, Style.pressedFillAlpha)
       : mouse.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, Style.hoverFillAlpha * 1.5)
       : Qt.rgba(fg.r, fg.g, fg.b, Style.normalFillAlpha)
  border.width: active ? 2 : Math.max(1, Style.normalBorderWidth)
  border.color: active ? accent : Qt.rgba(fg.r, fg.g, fg.b, mouse.containsMouse ? 0.8 : Math.max(0.5, Style.normalBorderAlpha))

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)
    Image {
      visible: chip.icon.toString() !== ""
      anchors.verticalCenter: parent.verticalCenter
      source: chip.icon
      width: 14; height: 14
      smooth: false
      sourceSize.width: 14; sourceSize.height: 14
    }
    T {
      ui: chip.ui
      sz: chip.sz
      anchors.verticalCenter: parent.verticalCenter
      text: (chip.check && chip.active ? "✓ " : "") + chip.label
      color: chip.fg
      font.bold: chip.active
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
