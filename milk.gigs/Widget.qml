import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Gig Board: a relaxed "jobs section of the newspaper" for contract work.
// The gigboard backend (~/projects/gig-board) writes ~/.cache/milk.gigs/board.json every 6 h;
// this widget only reads that file and launches `gigboard refresh|mark ...` detached.
// Style: ~/.claude/skills/milk-omarchy-widgets/SKILL.md (Chip / T kit, comfort panel).
Panel {
  id: root
  moduleName: "milk.gigs"

  // ---------- paths / commands ----------
  readonly property string home: Quickshell.env("HOME")
  readonly property string boardPath: home + "/.cache/milk.gigs/board.json"
  readonly property string prefsPath: home + "/.cache/milk.gigs/prefs.json"
  readonly property string gigboard: home + "/.local/bin/gigboard"

  // ---------- data ----------
  property var board: null            // last good board.json
  property bool readFailed: false      // latest read failed; `board` is the last good copy
  property bool loadedOnce: false
  property double now: Date.now()
  property string sessionSeen: ""      // board.seen_at captured when the panel opened (NEW badges stay put while reading)
  property bool captureSeen: false
  property bool kicked: false          // Refresh just clicked; show "Checking…" until the board answers
  property double kickedAt: 0
  property int fastTicks: 0            // quick re-reads after a command
  property var savedOverride: ({})     // id -> { v: bool, t: ms } optimistic star until the board agrees
  property var hiddenLocal: ({})       // id -> true, hidden right away while the backend catches up
  property var view: []                // filtered rows shown in the list
  property int matchCount: 0
  property string expandedId: ""
  property int cursor: 0

  // ---------- choices (persisted) ----------
  property var catSet: ({})            // selected categories; empty = Any (multi-select)
  readonly property int catCount: Object.keys(catSet).length
  property bool readable: false
  property int zoomStep: 0
  property bool comfortOpen: false
  property bool simple: false          // title + fit only
  property int limit: 0                // 0 = all, else top N
  property bool stripes: true
  property string readFamily: "Noto Sans"
  readonly property real zoom: [1, 1.15, 1.3][zoomStep]
  readonly property real cw: zoom * (readable ? 1.1 : 1)
  readonly property var limitSteps: [0, 10, 5]

  readonly property var cats: [
    { k: "ai", label: "AI" }, { k: "integration", label: "Integrations" }, { k: "apps", label: "Apps" },
    { k: "web", label: "Web" }, { k: "video", label: "Video" }, { k: "design", label: "Design" }, { k: "onsite", label: "On-site" }
  ]
  readonly property var catBadge: ({ ai: "AI", integration: "Integration", apps: "App", web: "Web", video: "Video",
                                     design: "Design", onsite: "On-site", other: "Other" })
  readonly property var sourceName: ({ kijiji: "Kijiji", castanet: "Castanet", craigslist: "Craigslist",
                                       wwr: "We Work Remotely", websweep: "Web search" })

  // ---------- derived ----------
  readonly property var listings: board && board.listings ? board.listings : []
  readonly property int newCount: board && board.counts ? (board.counts["new"] || 0) : 0
  // A crashed run must never leave "Checking…" stuck: trust `running` only if the board is under 15 min old.
  readonly property bool isRunning: !!board && !!board.running && minsAgo(board.updated) < 15
  readonly property bool checking: isRunning || kicked
  readonly property bool debounced: !!board && !!board.last_manual_refresh && minsAgo(board.last_manual_refresh) < 10
  readonly property string refreshLabel: checking ? "Checking…"
    : debounced ? "Fresh · " + (minsAgo(board.last_manual_refresh) < 1 ? "just now" : minsAgo(board.last_manual_refresh) + " min ago")
    : "Refresh"
  readonly property bool old: !!board && minsAgo(board.updated) > 8 * 60
  readonly property var hero: {
    for (var i = 0; i < view.length; i++) if (isNew(view[i])) return view[i]
    return null
  }

  // ---------- helpers ----------
  function fade(alpha) { return Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, alpha) }
  function parseIso(s) {
    if (!s) return null
    var d = new Date(String(s).replace(/(\.\d{3})\d+/, "$1"))   // Python writes microseconds; JS wants milliseconds
    return isNaN(d.getTime()) ? null : d
  }
  function minsAgo(s) { var d = parseIso(s); return d ? Math.max(0, Math.floor((now - d.getTime()) / 60000)) : 1e9 }
  function clock(s) {
    var d = parseIso(s)
    if (!d) return "never"
    var t = Qt.formatTime(d, "h:mm ap")
    return d.toDateString() === new Date(now).toDateString() ? t : Qt.formatDate(d, "ddd MMM d") + ", " + t
  }
  function postedText(l) {
    var d = parseIso(l.posted || l.first_seen)
    if (!d) return ""
    var days = Math.floor((new Date(now).setHours(0, 0, 0, 0) - new Date(d.getTime()).setHours(0, 0, 0, 0)) / 86400000)
    return days <= 0 ? "posted today" : days === 1 ? "posted yesterday" : "posted " + days + " d ago"
  }
  function placeText(l) { return l.remote ? "Remote" : (l.place || "Okanagan") }
  function srcName(s) { return sourceName[s] || s }
  function sourcesText(l) {
    var seen = {}, out = []
    ;(l.links || []).forEach(function(k) { if (!seen[k.source]) { seen[k.source] = true; out.push(srcName(k.source)) } })
    return out.join(" + ")
  }
  function subLine(l) {
    var parts = [placeText(l)]
    if (l.pay) parts.push(l.pay)
    var p = postedText(l); if (p) parts.push(p)
    var s = sourcesText(l); if (s) parts.push(s)
    return parts.join(" · ")
  }
  function isNew(l) { return sessionSeen === "" ? !!l["new"] : String(l.first_seen) > sessionSeen }
  function isSaved(l) { var o = savedOverride[l.id]; return o ? o.v : !!l.saved }
  function staleSources() {
    var out = []
    ;((board && board.sources) || []).forEach(function(s) {
      if (s.status === "ok") return
      out.push(srcName(s.name) + (!s.checked ? " not checked yet" : s.status === "blocked" ? " paused (blocked)" : " stale"))
    })
    return out
  }
  function footerText() {
    if (!board) return ""
    var parts = ["Updated " + clock(board.updated),
                 (view.length < listings.length ? view.length + " of " + listings.length : listings.length) + " shown"]
    if (board.counts && board.counts.filtered_out !== undefined) parts.push(board.counts.filtered_out + " filtered out")
    return parts.concat(staleSources()).join(" · ")
  }

  // ---------- load ----------
  function reload() { if (!loader.running) loader.running = true }
  function load(text) {
    now = Date.now()
    var data = null
    try { data = JSON.parse(text) } catch (e) { data = null }
    if (!data || !data.listings) { readFailed = loadedOnce || text.length > 0; loadedOnce = true; return }
    readFailed = false
    loadedOnce = true
    // drop optimistic state the board has caught up with (or that is older than 30 s)
    var so = {}, ids = {}
    data.listings.forEach(function(l) { ids[l.id] = l })
    for (var k in savedOverride) {
      var l = ids[k], o = savedOverride[k]
      if (l && !!l.saved !== o.v && now - o.t < 30000) so[k] = o
    }
    savedOverride = so
    var hl = {}
    for (var h in hiddenLocal) if (ids[h]) hl[h] = true
    hiddenLocal = hl
    if (kicked && (data.running || now - kickedAt > 6000)) kicked = false
    board = data
    if (captureSeen) { sessionSeen = data.seen_at || ""; captureSeen = false }
    rebuild()
  }
  function rebuild() {
    var out = []
    for (var i = 0; i < listings.length; i++) {
      var l = listings[i]
      if (hiddenLocal[l.id]) continue
      if (catCount > 0 && !catSet[l.category]) continue
      out.push(l)
    }
    matchCount = out.length
    view = limit > 0 ? out.slice(0, limit) : out
    cursor = Math.min(cursor, Math.max(0, view.length - 1))
  }

  // ---------- commands (detached: a refresh can outlive a shell restart) ----------
  function run(args) { Quickshell.execDetached([gigboard].concat(args)); fastTicks = 4 }
  function refresh() {
    if (checking) return
    kicked = true; kickedAt = Date.now()
    run(["refresh"])
  }
  function toggleSave(l) {
    if (!l) return
    var v = !isSaved(l), m = {}
    for (var k in savedOverride) m[k] = savedOverride[k]
    m[l.id] = { v: v, t: Date.now() }
    savedOverride = m
    run(["mark", v ? "save" : "unsave", l.id])
  }
  function hide(l) {
    if (!l) return
    var m = {}
    for (var k in hiddenLocal) m[k] = true
    m[l.id] = true
    hiddenLocal = m
    expandedId = ""
    rebuild()
    run(["mark", "hide", l.id])
  }
  function openLink(url) { if (url) Quickshell.execDetached(["xdg-open", url]) }
  function openFirst(l) { if (l && l.links && l.links.length) openLink(l.links[0].url) }

  // ---------- choices ----------
  function toggleCat(k) {
    var m = {}
    for (var c in catSet) m[c] = true
    if (m[k]) delete m[k]; else m[k] = true
    catSet = m
    apply()
  }
  function clearCats() { catSet = ({}); apply() }
  function apply() { expandedId = ""; rebuild(); savePrefs(); list.positionViewAtBeginning() }
  function cycleLimit() { limit = limitSteps[(limitSteps.indexOf(limit) + 1) % limitSteps.length]; apply() }
  function toggleExpand(l) { expandedId = (l && expandedId !== l.id) ? l.id : "" }
  function move(delta) {
    if (!view.length) return
    cursor = Math.max(0, Math.min(view.length - 1, cursor + delta))
    list.positionViewAtIndex(cursor, ListView.Contain)
  }
  function savePrefs() {
    Quickshell.execDetached(["python3", "-I", "-c",
      "import os,sys;os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True);open(sys.argv[1],'w').write(sys.argv[2])",
      prefsPath, JSON.stringify({ cats: Object.keys(catSet), comfortOpen: comfortOpen, readable: readable, zoomStep: zoomStep,
                                  simple: simple, limit: limit, stripes: stripes })])
  }
  function loadPrefs(text) {
    try {
      var p = JSON.parse(text), m = {}
      ;(p.cats || []).forEach(function(k) { m[k] = true })
      catSet = m
      comfortOpen = !!p.comfortOpen
      readable = !!p.readable
      zoomStep = Math.max(0, Math.min(2, p.zoomStep || 0))
      simple = !!p.simple
      limit = limitSteps.indexOf(p.limit) >= 0 ? p.limit : 0
      if (p.stripes !== undefined) stripes = !!p.stripes
      rebuild()
    } catch (e) {}
  }

  // NEW handling: keep this session's NEW badges while reading; mark everything seen when the panel closes.
  onOpenedChanged: {
    if (opened) {
      expandedId = ""
      cursor = 0
      if (board) sessionSeen = board.seen_at || ""   // until the fresh read below arrives
      captureSeen = true
      now = Date.now()
      reload()
    } else {
      if (newCount > 0) run(["mark", "seen"])
      sessionSeen = ""
      captureSeen = false
    }
  }

  implicitWidth: toggleButton.implicitWidth
  implicitHeight: toggleButton.implicitHeight

  Process {
    id: loader
    command: ["cat", root.boardPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }
  Process {   // first installed font from a dyslexia-friendly shortlist
    command: ["sh", "-c", "for f in 'Atkinson Hyperlegible Next' 'Atkinson Hyperlegible' 'Lexend' 'OpenDyslexic' 'Noto Sans' 'Liberation Sans'; do fc-list \"$f\" family | grep -qi \"^$f\" && { echo \"$f\"; exit; }; done"]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim().length) root.readFamily = text.trim() }
  }
  Process {
    command: ["cat", root.prefsPath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length) root.loadPrefs(text) }
  }
  // while open: every 30 s; while closed: every 5 min (keeps the bar count current)
  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: { root.now = Date.now(); root.reload() } }
  Timer { interval: 300000; running: !root.opened; repeat: true; triggeredOnStart: true; onTriggered: { root.now = Date.now(); root.reload() } }
  // right after a command, and every few seconds while a check runs and the panel is open
  Timer {
    interval: 2500; repeat: true
    running: root.fastTicks > 0 || (root.opened && root.checking)
    onTriggered: { if (root.fastTicks > 0) root.fastTicks--; root.now = Date.now(); root.reload() }
  }

  TextMetrics { id: barMetrics; font.family: toggleButton.fontFamily; font.pixelSize: Style.font.caption; text: "Gigs 88" }

  WidgetButton {
    id: toggleButton
    bar: root.bar
    text: root.newCount > 0 ? "Gigs " + Math.min(root.newCount, 99) : "Gigs"
    fontSize: Style.font.caption
    fixedWidth: root.bar && root.bar.vertical ? -1 : Math.ceil(barMetrics.advanceWidth + Style.spaceReal(8.5) * 2)
    tooltipText: !root.board ? "Gig Board: no board yet"
                 : (root.newCount > 0 ? root.newCount + " new gig" + (root.newCount === 1 ? "" : "s") : "Nothing new")
                   + " · " + root.listings.length + " on the board\nUpdated " + root.clock(root.board.updated)
                   + (root.readFailed ? "\nCouldn't read the latest board, showing the last good one" : "")
    onPressed: function(button) { if (root.opened) root.close(); else root.open() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: toggleButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(640 * root.cw))
    contentHeight: panel.fittedContentHeight(Style.space(720 * root.zoom))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.toggleExpand(root.view[root.cursor])
      onMoveRequested: function(dx, dy) { root.move(dy) }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "s") root.toggleSave(root.view[root.cursor])
        else if (text === "o") root.openFirst(root.view[root.cursor])
      }

      Column {
        id: controls
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        // ----- title row -----
        Item {
          width: parent.width
          height: Style.spacing.controlHeight * root.zoom
          T { ui: root; sz: Style.font.title; anchors.verticalCenter: parent.verticalCenter; text: "Gig Board"; font.bold: true }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Chip { ui: root; label: "Comfort"; active: root.comfortOpen; check: true; onClicked: { root.comfortOpen = !root.comfortOpen; root.savePrefs() } }
            Chip { ui: root; label: root.refreshLabel; active: root.checking; onClicked: root.refresh() }
          }
        }

        // ----- comfort (collapsed by default) -----
        Rectangle {
          visible: root.comfortOpen
          width: parent.width
          height: comfortFlow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          antialiasing: false
          color: root.fade(0.07)
          Flow {
            id: comfortFlow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)
            Chip { ui: root; label: "Readable font"; active: root.readable; check: true; onClicked: { root.readable = !root.readable; root.savePrefs() } }
            Chip { ui: root; label: "Text size " + Math.round(root.zoom * 100) + "%"; onClicked: { root.zoomStep = (root.zoomStep + 1) % 3; root.savePrefs() } }
            Chip { ui: root; label: "Simple view"; active: root.simple; check: true; onClicked: { root.simple = !root.simple; root.savePrefs() } }
            Chip { ui: root; label: root.limit ? "Show top " + root.limit : "Show all"; active: root.limit > 0; check: true; onClicked: root.cycleLimit() }
            Chip { ui: root; label: "Row stripes + ruler"; active: root.stripes; check: true; onClicked: { root.stripes = !root.stripes; root.savePrefs() } }
          }
        }

        T {
          ui: root; sz: Style.font.caption
          width: parent.width
          wrapMode: Text.Wrap
          text: "AI, integration, app, web and creative contract work. Okanagan in person, remote across Canada. Checked every 6 hours."
          opacity: 0.8
        }

        // ----- categories (multi-select; Any clears) -----
        Flow {
          width: parent.width
          spacing: Style.space(6)
          Chip { ui: root; sz: Style.font.body; label: "Any"; active: root.catCount === 0; onClicked: root.clearCats() }
          Repeater {
            model: root.cats
            delegate: Chip {
              required property var modelData
              ui: root; sz: Style.font.body
              label: modelData.label
              active: !!root.catSet[modelData.k]
              check: true
              onClicked: root.toggleCat(modelData.k)
            }
          }
        }

        // ----- status lines (never colour alone: they say what's wrong) -----
        T {
          visible: root.checking
          ui: root; sz: Style.font.caption
          width: parent.width
          wrapMode: Text.Wrap
          text: "Checking the boards now. This can take a few minutes; you can close this panel."
          font.bold: true
        }
        T {
          visible: root.readFailed || root.old
          ui: root; sz: Style.font.caption
          width: parent.width
          wrapMode: Text.Wrap
          color: Commons.Color.urgent
          text: root.readFailed ? "Couldn't read the latest board. Showing the last good copy (updated " + root.clock(root.board ? root.board.updated : "") + ")."
                : "This board is from " + root.clock(root.board ? root.board.updated : "") + ". A scheduled check may have been missed; press Refresh."
        }

        // ----- hero: best-fit NEW listing -----
        Rectangle {
          id: heroCard
          readonly property var m: root.hero
          visible: m !== null
          width: parent.width
          height: heroCol.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          antialiasing: false
          color: heroMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.20)
                                         : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
          border.width: 2
          border.color: Commons.Color.accent
          Column {
            id: heroCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(3)
            T { ui: root; sz: Style.font.caption; text: "BEST NEW FIT"; font.bold: true; color: Commons.Color.accent }
            T {
              ui: root; sz: Style.font.title
              width: parent.width
              text: heroCard.m ? heroCard.m.title : ""
              font.bold: true
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            T {
              ui: root; sz: Style.font.body
              width: parent.width
              text: heroCard.m ? heroCard.m.fit + "/10 fit · " + root.placeText(heroCard.m) + (heroCard.m.pay ? " · " + heroCard.m.pay : "")
                                 + " · " + (root.catBadge[heroCard.m.category] || "Other") : ""
              elide: Text.ElideRight
            }
            T {
              visible: !root.simple && !!heroCard.m && !!heroCard.m.why
              ui: root; sz: Style.font.body
              width: parent.width
              text: heroCard.m && heroCard.m.why ? heroCard.m.why : ""
              wrapMode: Text.Wrap
              opacity: 0.85
            }
            T {
              ui: root; sz: Style.font.caption
              text: heroCard.m && heroCard.m.links && heroCard.m.links.length ? "Click to open the ad on " + root.srcName(heroCard.m.links[0].source) + " ↗" : ""
              opacity: 0.75
            }
          }
          MouseArea { id: heroMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openFirst(heroCard.m) }
        }

        // nothing new, but the board has listings
        T {
          visible: root.hero === null && root.view.length > 0
          ui: root; sz: Style.font.body
          width: parent.width
          wrapMode: Text.Wrap
          text: "Nothing new since you last looked. Checked " + root.clock(root.board ? root.board.updated : "") + "."
          opacity: 0.85
        }
      }

      // ----- list -----
      ListView {
        id: list
        anchors.top: controls.bottom
        anchors.topMargin: Style.space(8)
        anchors.bottom: footLine.top
        anchors.bottomMargin: Style.space(6)
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        spacing: Style.space(2)
        model: root.view
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool expanded: root.expandedId === modelData.id
          readonly property bool saved: root.isSaved(modelData)
          readonly property bool fresh: root.isNew(modelData)
          width: list.width
          height: rowColumn.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          antialiasing: false
          color: expanded ? root.fade(Style.selectedFillAlpha)
               : hover.containsMouse && root.stripes ? root.fade(Style.hoverFillAlpha * 2)
               : index === root.cursor && root.opened ? root.fade(Style.selectedFillAlpha * 0.7)
               : hover.containsMouse ? root.fade(Style.hoverFillAlpha)
               : root.stripes && index % 2 === 1 ? root.fade(0.06) : "transparent"
          border.width: expanded ? Style.selectedBorderWidth : 0
          border.color: Commons.Color.accent

          Rectangle {   // reading ruler on the hovered row
            visible: root.stripes && hover.containsMouse
            width: 4
            antialiasing: false
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.topMargin: 3; anchors.bottomMargin: 3
            color: Commons.Color.accent
          }

          Column {
            id: rowColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Math.max(Style.space(root.simple ? 30 : 40) * root.zoom, nameCell.height)

              Row {
                id: lead
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Item {   // star = save
                  id: starBox
                  width: Style.space(26) * root.zoom
                  height: Style.space(32) * root.zoom
                  anchors.verticalCenter: parent.verticalCenter
                  T {
                    ui: root; sz: Style.font.body + 3
                    anchors.centerIn: parent
                    text: row.saved ? "★" : "☆"
                    color: row.saved ? Commons.Color.accent : root.barForeground
                    opacity: row.saved ? 1 : 0.6
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSave(row.modelData) }
                }
                Rectangle {   // fit score; strong fits (7+) get an accent box AND bold
                  width: Style.space(44) * root.cw
                  height: Style.space(24) * root.zoom
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  antialiasing: false
                  color: row.modelData.fit >= 7 ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.28) : "transparent"
                  T {
                    ui: root; sz: Style.font.caption
                    anchors.centerIn: parent
                    text: row.modelData.fit + "/10"
                    font.bold: row.modelData.fit >= 7
                    opacity: row.modelData.fit >= 7 ? 1 : 0.85
                  }
                }
              }

              Item {
                id: nameCell
                anchors.left: lead.right
                anchors.leftMargin: Style.space(8)
                anchors.right: newBadge.visible ? newBadge.left : parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: nameLine.height + (sub.visible ? sub.height : 0)
                Row {
                  id: nameLine
                  spacing: Style.space(6)
                  T {
                    id: nameText
                    ui: root; sz: Style.font.body
                    width: Math.min(implicitWidth, nameCell.width - catTag.width - Style.space(6))
                    text: row.modelData.title
                    elide: Text.ElideRight
                    font.bold: true
                  }
                  Rectangle {
                    id: catTag
                    anchors.verticalCenter: nameText.verticalCenter
                    width: catText.implicitWidth + Style.space(10)
                    height: catText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius
                    antialiasing: false
                    color: root.fade(0.16)
                    T { id: catText; ui: root; sz: Style.font.caption - 1; anchors.centerIn: parent; text: root.catBadge[row.modelData.category] || "Other" }
                  }
                }
                T {
                  id: sub
                  visible: !root.simple
                  ui: root; sz: Style.font.caption
                  anchors.top: nameLine.bottom
                  anchors.topMargin: Style.space(2)
                  width: parent.width
                  text: root.subLine(row.modelData)
                  elide: Text.ElideRight
                  opacity: 0.78
                }
              }

              Rectangle {   // NEW: text + accent border, never colour alone
                id: newBadge
                visible: row.fresh
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: newText.implicitWidth + Style.space(10)
                height: newText.implicitHeight + Style.space(4)
                radius: Style.cornerRadius
                antialiasing: false
                color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.20)
                border.width: 1
                border.color: Commons.Color.accent
                T { id: newText; ui: root; sz: Style.font.caption - 1; anchors.centerIn: parent; text: "NEW"; font.bold: true }
              }

              MouseArea {
                id: hover
                anchors.fill: parent
                anchors.leftMargin: starBox.width + 4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.cursor = row.index; root.toggleExpand(row.modelData) }
              }
            }

            // ----- inline details -----
            Column {
              visible: row.expanded
              width: parent.width
              spacing: Style.space(6)
              T {
                visible: !!row.modelData.why
                ui: root; sz: Style.font.body
                width: parent.width
                wrapMode: Text.Wrap
                text: row.modelData.why || ""
                opacity: 0.9
              }
              T {
                visible: root.simple
                ui: root; sz: Style.font.caption
                width: parent.width
                wrapMode: Text.Wrap
                text: root.subLine(row.modelData)
                opacity: 0.78
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: row.modelData.links || []
                  delegate: Chip {
                    required property var modelData
                    ui: root
                    label: "Open on " + root.srcName(modelData.source) + " ↗"
                    onClicked: root.openLink(modelData.url)
                  }
                }
                Chip { ui: root; label: row.saved ? "★ Saved" : "☆ Save"; active: row.saved; onClicked: root.toggleSave(row.modelData) }
                Chip { ui: root; label: "Hide this gig"; onClicked: root.hide(row.modelData) }
              }
            }
          }
        }

        // ----- empty states (friendly and honest) -----
        T {
          anchors.centerIn: parent
          visible: root.view.length === 0
          width: parent.width * 0.85
          ui: root; sz: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: !root.board ? (root.loadedOnce ? "No board yet. Press Refresh to check the boards now." : "Reading the board…")
                : root.listings.length === 0 ? "Nothing new worth your time right now. Checked " + root.clock(root.board.updated) + "."
                : "No gigs in these categories right now. Tap Any to see all " + root.listings.length + "."
          opacity: 0.8
        }
      }

      T {
        id: footLine
        ui: root; sz: Style.font.caption
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        text: root.footerText()
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        opacity: 0.75
      }
    }
  }
}
