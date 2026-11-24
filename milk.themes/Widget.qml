import QtQuick
import qs.Commons
import qs.Ui

// Themes button (milk style): one square icon in the bar, same size as the weather button.
// Left click  = Omarchy theme switcher (preview thumbnails, type to filter, Enter to apply).
// Right click = background switcher for the current theme.
BarWidget {
  id: root
  moduleName: "milk.themes"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F03D8}"
    slotSize: Style.bar.statusSlot
    tooltipText: "Themes (right click: backgrounds)"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-theme-bg-switcher")
      else root.bar.run("omarchy-theme-switcher")
    }
  }
}
