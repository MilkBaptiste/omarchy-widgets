import QtQuick
import qs.Commons
import qs.Commons as Commons

// Milk-style text box: square, accent border while focused. Tells the widget root when typing
// so panel shortcut keys are paused (root.typing counts focused fields).
Rectangle {
  id: f
  property var ui: null
  property alias text: edit.text
  property string placeholder: ""
  property int lines: 1
  readonly property bool focused: edit.activeFocus
  signal accepted()
  signal escaped()

  implicitHeight: Math.max(Style.spacing.controlHeight * (ui ? ui.zoom : 1), edit.contentHeight + Style.space(14))
  radius: Style.cornerRadius
  antialiasing: false
  color: ui ? ui.fade(0.05) : "transparent"
  border.width: edit.activeFocus ? 2 : 1
  border.color: edit.activeFocus ? Commons.Color.accent : (ui ? ui.fade(0.6) : "gray")

  onFocusedChanged: if (ui) ui.typing += focused ? 1 : -1
  Component.onDestruction: if (focused && ui) ui.typing -= 1
  function grab() { edit.forceActiveFocus() }

  TextEdit {
    id: edit
    anchors.fill: parent
    anchors.margins: Style.space(7)
    wrapMode: TextEdit.Wrap
    color: f.ui ? f.ui.barForeground : Commons.Color.foreground
    selectionColor: Commons.Color.accent
    selectedTextColor: Commons.Color.background
    font.family: f.ui && f.ui.readable ? f.ui.readFamily : Style.font.family
    font.pixelSize: Style.font.body * (f.ui ? f.ui.zoom : 1)
    font.letterSpacing: f.ui && f.ui.readable ? 0.7 : 0
    font.wordSpacing: f.ui && f.ui.readable ? 3 : 0
    Keys.onPressed: function(event) {
      if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier) && f.lines === 1) { f.accepted(); event.accepted = true }
      else if (event.key === Qt.Key_Escape) { edit.focus = false; f.escaped(); event.accepted = true }
    }
    T { visible: edit.text === "" && !edit.preeditText; ui: f.ui; opacity: 0.6; text: f.placeholder; width: parent.width; elide: Text.ElideRight }
  }
}
