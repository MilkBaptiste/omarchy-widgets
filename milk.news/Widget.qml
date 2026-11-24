import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "milk.news"

  readonly property var categories: ["All", "World", "Geo", "Tech", "Markets", "Linux"]
  readonly property var tabs: ["All", "World", "Geo", "Tech", "Markets"]
  readonly property var visibleTabs: tabs.indexOf(category) >= 0 ? tabs : tabs.concat([category])
  readonly property var categoryEmoji: ({"All": "📰", "World": "🌍", "Geo": "🌐", "Tech": "💻", "Markets": "📈", "Linux": "🐧"})
  property var items: []
  property var failed: []
  property double updated: 0
  property double now: Date.now()
  property string category: "All"
  property string topic: ""          // topic emoji filter, set from the Topics row
  property bool browsing: false      // category screen instead of the headline list
  property int browseCursor: 0
  property bool bySeverity: false    // last 48 h, most severe first
  property int cursor: 0
  property int tickerIndex: 0
  readonly property var topicNames: ({"⚔️": "Conflict", "🏛️": "Politics", "✊": "Protests", "🔒": "Security", "🤖": "AI", "🌪️": "Disasters", "🩺": "Health", "🛢️": "Energy", "📈": "Markets", "🚀": "Space", "🐧": "Linux", "📦": "Releases", "💻": "Tech", "🌍": "World", "🌐": "Geo", "📰": "General"})
  readonly property var inCategory: category === "All" ? items : items.filter(function(item) { return item.cat === category })
  readonly property var sections: categories.map(function(name) {
    return { kind: "section", key: name, emoji: categoryEmoji[name], name: name === "All" ? "Everything" : name,
             count: name === "All" ? items.length : items.filter(function(item) { return item.cat === name }).length }
  })
  readonly property var topics: {
    var counts = {}
    items.forEach(function(item) { counts[item.emoji] = (counts[item.emoji] || 0) + 1 })
    return Object.keys(counts).sort(function(a, b) { return counts[b] - counts[a] }).map(function(emoji) {
      return { kind: "topic", key: emoji, emoji: emoji, name: topicNames[emoji] || "Other", count: counts[emoji] }
    })
  }
  readonly property var shown: {
    var out = topic === "" ? inCategory : inCategory.filter(function(item) { return item.emoji === topic })
    if (!bySeverity) return out
    var cutoff = now / 1000 - 48 * 3600
    return out.filter(function(item) { return item.ts >= cutoff }).sort(function(a, b) {
      return (b.bomb - a.bomb) || (b.fire - a.fire) || (b.ts - a.ts)
    })
  }
  readonly property var tickerItem: items.length > 0 ? items[tickerIndex % Math.min(items.length, 30)] : null
  readonly property int tickerChars: 72
  property bool fitCompact: false        // set by milk.bar-fit
  readonly property real tickerWidth: Style.space(440)
  // Collapse arrow: the user's own choice, saved in ~/.cache/milk.bar-fit/milk.news.json.
  // milk.bar-fit reads fitPinned and also shrinks this widget on its own if the bar gets too full.
  property bool fitPinned: false
  readonly property string fitPath: Quickshell.env("HOME") + "/.cache/milk.bar-fit/milk.news.json"
  function setFitPinned(value) {
      fitPinned = value
      fitCompact = value
      Quickshell.execDetached(["python3", "-I", "-c",
          "import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'w').write(json.dumps({'collapsed': sys.argv[2]=='1'}))",
          fitPath, value ? "1" : "0"])
  }
  FileView {
      path: root.fitPath
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: { try { root.fitPinned = !!JSON.parse(text()).collapsed } catch (e) { root.fitPinned = false } }
  }

  function ago(ts) {
    if (!ts) return ""
    var minutes = Math.max(0, Math.round((now / 1000 - ts) / 60))
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + "m"
    if (minutes < 1440) return Math.round(minutes / 60) + "h"
    return Math.round(minutes / 1440) + "d"
  }
  function flames(item) { return (item.bomb ? "💣" : "") + "🔥".repeat(item.fire || 1) }
  function clip(text, limit) { return text.length > limit ? text.slice(0, limit - 1) + "…" : text }
  function refresh() { if (!fetcher.running) fetcher.running = true }
  function openItem(item) {
    if (!item) return
    Quickshell.execDetached(["xdg-open", item.link])
    close()
  }
  function setCategory(name) {
    category = name
    topic = ""
    cursor = 0
    list.positionViewAtBeginning()
  }
  function shiftCategory(direction) {
    var next = (visibleTabs.indexOf(category) + direction + visibleTabs.length) % visibleTabs.length
    setCategory(visibleTabs[next])
  }
  function browseEntries() { return sections.concat(topics) }
  function chooseEntry(entry) {
    if (!entry) return
    if (entry.kind === "section") setCategory(entry.key)
    else { category = "All"; topic = entry.key; cursor = 0; list.positionViewAtBeginning() }
    browsing = false
  }
  function moveBrowse(dx, dy) {
    var last = browseEntries().length - 1
    browseCursor = Math.max(0, Math.min(last, browseCursor + dx + dy * 3))
  }
  function setTopic(emoji) {
    topic = topic === emoji ? "" : emoji
    cursor = 0
    list.positionViewAtBeginning()
  }
  function toggleSeverity() {
    bySeverity = !bySeverity
    cursor = 0
    list.positionViewAtBeginning()
  }
  function moveCursor(delta) {
    if (shown.length === 0) return
    cursor = Math.max(0, Math.min(shown.length - 1, cursor + delta))
    list.positionViewAtIndex(cursor, ListView.Contain)
  }
  function load(text) {
    try {
      var data = JSON.parse(text)
      items = data.items || []
      failed = data.failed || []
      updated = data.updated || 0
      if (cursor >= shown.length) cursor = 0
    } catch (error) { console.warn("News:", error) }
  }

  implicitWidth: ticker.implicitWidth + fitArrow.implicitWidth
  implicitHeight: ticker.implicitHeight

  Process {
    id: fetcher
    command: ["python3", "-I", Qt.resolvedUrl("fetch.py").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.load(text)
    }
  }
  Process {
    id: cached
    command: ["cat", Quickshell.env("HOME") + "/.cache/milk-news/items.json"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.length > 0 && root.items.length === 0) root.load(text)
    }
  }
  Timer {
    interval: 600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now(); root.refresh() }
  }
  Timer {
    interval: 12000
    running: !root.opened
    repeat: true
    onTriggered: { root.now = Date.now(); root.tickerIndex += 1 }
  }

  WidgetButton {
    id: ticker
    bar: root.bar
    fontSize: Style.font.caption
    labelVisible: false          // the stock label uses native rendering, which drops color emoji
    hasVisualContent: true
    fixedWidth: root.fitCompact ? tickerLabel.implicitWidth + Style.space(14) : root.tickerWidth
    Text {
      id: tickerLabel
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(7)
      width: root.fitCompact ? implicitWidth : root.tickerWidth - Style.space(14)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: root.fitCompact ? "📰" + (root.tickerItem && root.tickerItem.bomb ? "💣" : "") : root.tickerItem ? root.tickerItem.emoji + " " + root.flames(root.tickerItem) + "  " + root.tickerItem.source + "  " + root.clip(root.tickerItem.title, root.tickerChars) : "News…"
    }
    tooltipText: root.tickerItem ? root.tickerItem.title + "\n" + root.tickerItem.source + " · " + root.ago(root.tickerItem.ts) + " ago · severity " + (root.tickerItem.fire || 1) + "/3\nClick for all headlines" : "Loading headlines"
    onPressed: function(button) {
      if (button === Qt.RightButton) { root.tickerIndex += 1; return }
      if (root.opened) root.close(); else root.open()
    }
    onWheelMoved: function(delta) { root.tickerIndex = Math.max(0, root.tickerIndex + (delta > 0 ? -1 : 1)) }
  }

  WidgetButton {
      id: fitArrow
      bar: root.bar
      anchors.left: ticker.right
      anchors.verticalCenter: ticker.verticalCenter
      fontSize: Style.font.caption
      horizontalMargin: 4
      text: root.fitPinned ? "▸" : "◂"
      tooltipText: root.fitPinned ? "Expand News" : root.fitCompact ? "Shrunk automatically: the bar is full.\nClick to keep it collapsed." : "Collapse News"
      onPressed: function(b) { root.setFitPinned(!root.fitPinned) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: ticker
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: { if (root.browsing) root.browsing = false; else root.close() }
      onActivateRequested: { if (root.browsing) root.chooseEntry(root.browseEntries()[root.browseCursor]); else root.openItem(root.shown[root.cursor]) }
      onTabRequested: function(direction) { root.shiftCategory(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.browsing) root.moveBrowse(dx, dy)
        else if (dx !== 0) root.shiftCategory(dx)
        else root.moveCursor(dy)
      }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "g") { root.cursor = 0; list.positionViewAtBeginning() }
        else if (text === "G") root.moveCursor(root.shown.length)
        else if (text === "s") root.toggleSeverity()
        else if (text === "t") { root.browsing = !root.browsing; root.browseCursor = 0 }
        else if (text >= "1" && text <= String(root.tabs.length)) { root.browsing = false; root.setCategory(root.tabs[Number(text) - 1]) }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          Text {
            id: heading
            text: "News"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Item { width: parent.width - heading.width - status.width; height: 1 }
          Text {
            id: status
            text: (root.bySeverity ? "🔥 by severity · last 48h · " : "") + (root.failed.length > 0 ? root.failed.length + " feed(s) failed · " : "") + (root.updated ? "updated " + root.ago(root.updated) + " ago" : "loading…")
            color: root.failed.length > 0 ? Color.urgent : root.barForeground
            opacity: root.failed.length > 0 ? 1 : 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: heading.verticalCenter
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.visibleTabs
            Button {
              required property string modelData
              text: root.categoryEmoji[modelData] + " " + modelData
              selected: !root.browsing && root.topic === "" && root.category === modelData
              foreground: root.barForeground
              bordered: true
              fontSize: Style.font.caption
              onClicked: { root.browsing = false; root.setCategory(modelData) }
            }
          }
          Button {
            text: "🗂️" + (root.topic !== "" ? " " + root.topic : "")
            tooltipText: "All categories (t)"
            selected: root.browsing || root.topic !== ""
            foreground: root.barForeground
            bordered: true
            fontSize: Style.font.caption
            onClicked: { root.browsing = !root.browsing; root.browseCursor = 0 }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.barForeground }

        Column {
          id: browse
          visible: root.browsing
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "Sections"
            color: root.barForeground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Grid {
            columns: 3
            spacing: Style.space(6)
            Repeater {
              model: root.sections
              Button {
                required property var modelData
                required property int index
                width: (browse.width - Style.space(12)) / 3
                text: modelData.emoji + " " + modelData.name + "  " + modelData.count
                selected: root.topic === "" && root.category === modelData.key
                hasCursor: root.browseCursor === index
                foreground: root.barForeground
                bordered: true
                fontSize: Style.font.body
                onClicked: root.chooseEntry(modelData)
              }
            }
          }
          Text {
            text: "Topics"
            color: root.barForeground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Grid {
            columns: 3
            spacing: Style.space(6)
            Repeater {
              model: root.topics
              Button {
                required property var modelData
                required property int index
                width: (browse.width - Style.space(12)) / 3
                text: modelData.emoji + " " + modelData.name + "  " + modelData.count
                selected: root.topic === modelData.key
                hasCursor: root.browseCursor === root.sections.length + index
                foreground: root.barForeground
                bordered: true
                fontSize: Style.font.body
                onClicked: root.chooseEntry(modelData)
              }
            }
          }
        }

        ListView {
          id: list
          visible: !root.browsing
          width: parent.width
          height: Math.min(contentHeight, Style.space(500))
          clip: true
          model: root.shown
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.cursor
            width: list.width
            height: Math.max(rowText.implicitHeight, thumb.visible ? thumb.height : 0) + Style.space(14)
            radius: Style.cornerRadius
            color: current ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, Style.selectedFillAlpha)
                           : (hover.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, Style.hoverFillAlpha) : "transparent")
            border.width: current ? Style.selectedBorderWidth : 0
            border.color: Color.accent

            Rectangle {
              visible: row.current
              width: Math.max(2, Style.space(3))
              height: parent.height - Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              color: Color.accent
            }
            Rectangle {
              id: thumb
              visible: row.modelData.image !== null && row.modelData.image !== undefined && photo.status !== Image.Error
              width: visible ? Style.space(64) : 0
              height: Style.space(48)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
              clip: true
              Image {
                id: photo
                anchors.fill: parent
                source: row.modelData.image || ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 160
                sourceSize.height: 120
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
              }
            }
            Column {
              id: rowText
              anchors.left: thumb.visible ? thumb.right : parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(3)
              Text {
                width: parent.width
                text: row.modelData.emoji + "  " + row.modelData.title
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: row.current
              }
              Text {
                visible: text.length > 0
                width: parent.width
                text: row.modelData.summary || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: root.barForeground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                text: root.flames(row.modelData) + "   " + row.modelData.source + "  ·  " + row.modelData.cat + "  ·  " + root.ago(row.modelData.ts)
                color: root.barForeground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openItem(row.modelData)
            }
          }
        }

        Text {
          visible: !root.browsing && root.shown.length === 0
          width: parent.width
          text: root.updated ? "No headlines in this category." : "Fetching headlines…"
          color: root.barForeground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "🔥 low · 🔥🔥 notable · 🔥🔥🔥 grave · 💣 new conflict      j/k move · h/l tab · s severity 48h · t categories · Enter open · r refresh"
          color: root.barForeground
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
