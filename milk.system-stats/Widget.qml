import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "milk.system-stats"
  property var stats: ({})
  property var previous: null
  property int cpuPercent: -1
  property double updated: 0
  property double now: Date.now()
  property string selected: "CPU"
  property Item selectedButton: buttons
  readonly property bool fresh: updated > 0 && now - updated < 10000
  readonly property int memoryPercent: stats.memoryTotal ? Math.round(stats.memoryUsed / stats.memoryTotal * 100) : -1
  readonly property string details: {
    if (!fresh) return "Waiting for fresh readings…"
    if (selected === "CPU") return stats.cpuName + "\n\nUsage: " + percent(cpuPercent) + "\nLoad (1 / 5 / 15 min): " + (stats.load || []).join(" / ")
    if (selected === "RAM") return "Memory usage: " + percent(memoryPercent) + "\n\nUsed: " + gib(stats.memoryUsed) + " GiB\nTotal: " + gib(stats.memoryTotal) + " GiB\nAvailable: " + gib(stats.memoryTotal - stats.memoryUsed) + " GiB\n\nUses Linux MemAvailable, including reclaimable cache."
    return (stats.gpuName || "GPU") + "\n\nCurrent clock: " + (stats.gpuMHz === undefined ? "Unavailable" : stats.gpuMHz + " MHz") + "\nClock range: " + (stats.gpuMin || "—") + "–" + (stats.gpuMax || "—") + " MHz\n\nClock speed is shown here. GPU utilization is unavailable with the current monitoring setup."
  }
  function percent(value) { return value >= 0 ? value + "%" : "—" }
  function gib(value) { return (value / 1048576).toFixed(1) }
  function refresh() { if (!reader.running) reader.running = true }
  function showMetric(metric, button) {
    selectedButton = button
    if (opened && selected === metric) close()
    else { selected = metric; open() }
  }
  function launchMonitor() {
    if (bar) bar.run("omarchy-launch-tui btop")
    close()
  }
  implicitWidth: buttons.implicitWidth
  implicitHeight: buttons.implicitHeight
  Process {
    id: reader
    command: ["python3", Qt.resolvedUrl("stats.py").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (root.previous && next.total > root.previous.total) {
            var total = next.total - root.previous.total
            var idle = next.idle - root.previous.idle
            root.cpuPercent = Math.max(0, Math.min(100, Math.round(100 * (total - idle) / total)))
          }
          root.previous = next
          root.stats = next
          root.updated = Date.now()
        } catch (error) { console.warn("System stats:", error) }
      }
    }
  }
  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now(); root.refresh() }
  }
  Row {
    id: buttons
    MetricButton { metric: "CPU"; value: root.fresh ? root.percent(root.cpuPercent) : "—" }
    MetricButton { metric: "RAM"; value: root.fresh ? root.percent(root.memoryPercent) : "—" }
    MetricButton { metric: "GPU"; value: root.fresh && root.stats.gpuMHz !== undefined ? root.stats.gpuMHz + "MHz" : "—" }
  }
  component MetricButton: WidgetButton {
    id: metricButton
    required property string metric
    required property string value
    bar: root.bar
    text: metric + " " + value
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: metric + " details"
    onPressed: root.showMetric(metric, metricButton)
  }
  KeyboardPanel {
    id: panel
    anchorItem: root.selectedButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(400))
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.launchMonitor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)
        Text {
          text: root.selected === "RAM" ? "Memory" : root.selected
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        PanelSeparator { width: parent.width; foreground: root.barForeground }
        Text {
          width: parent.width
          text: root.details
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Button {
          text: "Open system monitor"
          foreground: root.barForeground
          bordered: true
          onClicked: root.launchMonitor()
        }
      }
    }
  }
}
