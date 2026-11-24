import QtQuick
import Qt5Compat.GraphicalEffects

// Round profile photo (emoji in a round tile when the bot has no photo).
Item {
  id: av
  property string source: ""      // absolute file path, or ""
  property string emoji: ""
  property real size: 40
  property color fill: "#333"
  property color edge: "#888"
  width: size
  height: size

  Rectangle { anchors.fill: parent; radius: width / 2; color: av.fill; antialiasing: true }
  Image {
    id: img
    anchors.fill: parent
    source: av.source ? "file://" + av.source : ""
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: 128
    sourceSize.height: 128
    asynchronous: true
    visible: false
  }
  Rectangle { id: mask; anchors.fill: parent; radius: width / 2; visible: false; antialiasing: true }
  OpacityMask { anchors.fill: parent; source: img; maskSource: mask; visible: img.status === Image.Ready }
  Text {
    visible: img.status !== Image.Ready
    anchors.centerIn: parent
    text: av.emoji
    font.family: "Noto Color Emoji"
    font.pixelSize: av.size * 0.5
  }
  Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: av.edge; antialiasing: true }
}
