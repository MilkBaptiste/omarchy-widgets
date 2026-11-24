import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

Panel {
  id: root
  moduleName: "milk.llm-rankings"

  // ---------- data ----------
  property var items: []          // every scored model, enriched
  property var view: []           // filtered + sorted rows shown in the list
  property var chartPts: []       // filtered models that have a price (for the chart)
  property int matchCount: 0
  property var providers: []
  property var missingLabs: []
  property string fetchMode: "--auto"
  property var levelsPresent: []
  property double updated: 0
  property var indexVersion: null
  property bool needsKey: false
  property double now: Date.now()
  property string error: ""
  property bool stale: false
  readonly property bool old: stale || (updated > 0 && now / 1000 - updated > 10800)

  // ---------- choices (all persisted) ----------
  property string tab: "smart"    // smart | cheap | value | fast | latency
  property bool reverse: false
  property var levelSet: ({})     // selected reasoning levels; empty = any (multi-select)
  property var labSet: ({})       // selected labs; "__other" = labs not in labs.json; empty = all (multi-select)
  readonly property int levelCount: Object.keys(levelSet).length
  readonly property int labCount: Object.keys(labSet).length
  property int minScore: 30
  property bool pinsOnly: false
  property var pins: ({})         // model id -> true
  property string viewMode: "list" // list | chart | compare
  property string compareA: "smart"
  property string compareB: "cheap"
  property var cmpA: []           // top picks for category A (filters applied)
  property var cmpB: []
  // comfort (ADHD / dyslexia)
  property bool readable: false   // readable proportional font + spacing
  property int zoomStep: 0        // 0=100% 1=115% 2=130%
  property bool simple: false     // fewer columns
  property int limit: 0           // 0 = all, else show top N only
  property bool stripes: true     // zebra rows + hover ruler
  property bool comfortOpen: false

  property string expandedId: ""
  property int cursor: 0

  readonly property real zoom: [1, 1.15, 1.3][zoomStep]
  readonly property real cw: zoom * (readable ? 1.1 : 1)
  property string readFamily: "Noto Sans"   // replaced at startup by the best installed readable font
  readonly property int mascotPx: Math.round(zoom * 2) * 10

  readonly property var tabs: [
    { id: "smart",   label: "Smartest",  hero: "Smartest right now",  about: "Highest Intelligence Index first." },
    { id: "cheap",   label: "Cheapest",  hero: "Cheapest decent model", about: "Lowest blended price first (3 input : 1 output tokens). Min IQ hides weak models." },
    { id: "value",   label: "Best value", hero: "Most brains per dollar", about: "IQ points per blended dollar: smart AND cheap." },
    { id: "fast",    label: "Fastest",   hero: "Fastest typist",      about: "Most output tokens per second first." },
    { id: "latency", label: "Quickest start", hero: "Quickest to answer", about: "Lowest time to first token first." }
  ]
  readonly property var levelOrder: ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
  readonly property var levelLabel: ({ off: "Off", minimal: "Min", low: "Low", medium: "Med", high: "High", xhigh: "XHigh", max: "Max" })
  readonly property var minSteps: [0, 30, 40, 50]
  readonly property var limitSteps: [0, 10, 5]
  readonly property string prefsPath: Quickshell.env("HOME") + "/.cache/milk-llm-rankings/prefs.json"
  readonly property string cachePath: Quickshell.env("HOME") + "/.cache/milk-llm-rankings/artificial-analysis.json"
  readonly property var mascotAlias: ({ spacexai: "xai", xai: "xai", openai: "openai", anthropic: "anthropic", google: "google", meta: "meta",
                                        deepseek: "deepseek", mistral: "mistral", alibaba: "alibaba", kimi: "kimi", moonshotai: "kimi",
                                        xiaomi: "xiaomi", nvidia: "nvidia" })
  readonly property var mascotColor: ({ anthropic: "#d97757", openai: "#10a37f", google: "#4285f4", meta: "#0866ff", deepseek: "#4d6bfe",
                                        mistral: "#fa520f", alibaba: "#7b5cff", kimi: "#8fa8e8", xai: "#e8e8e8", xiaomi: "#ff6900",
                                        nvidia: "#76b900", robot: "#9aa5b1" })

  // column widths (shared by header and rows)
  readonly property real cIq: Style.space(46) * cw
  readonly property real cMoney: Style.space(50) * cw
  readonly property real cSpeed: Style.space(46) * cw
  readonly property real cLat: Style.space(52) * cw
  readonly property real cValue: Style.space(46) * cw
  readonly property real cKey: Style.space(84) * cw

  // ---------- helpers ----------
  function mascotSlug(p) { return mascotAlias[String(p).toLowerCase().replace(/[^a-z0-9]/g, "")] || "robot" }
  function mascotUrl(p) { return Qt.resolvedUrl("mascots/" + mascotSlug(p) + ".png") }
  function providerColor(p) { return mascotColor[mascotSlug(p)] }
  function fade(alpha) { return Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, alpha) }
  function money(v) { return v === null || v === undefined ? "—" : v < 0.1 && v > 0 ? "$" + Number(v).toFixed(3) : "$" + Number(v).toFixed(2) }
  function num(v, d) { return v === null || v === undefined ? "—" : Number(v).toFixed(d) }
  function iq(m) { return m.score === null || m.score === undefined ? "—" : m.score }
  function levelText(it) { return it.level ? levelLabel[it.level] : "" }
  // auto = hourly timer / startup / opening a stale panel; manual = Refresh button or right-click
  function refresh(auto) { if (fetcher.running) return; fetchMode = auto ? "--auto" : "--manual"; fetcher.running = true }
  function setupKey() { Quickshell.execDetached(["omarchy-launch-tui", "python3", "-I", Qt.resolvedUrl("setup-key.py").toString().replace("file://", "")]); close() }
  function visit(item) { if (item) Quickshell.execDetached(["xdg-open", item.url]) }
  function copyName(item) { if (item) Quickshell.execDetached(["wl-copy", item.name]) }
  function tabInfo(id) { for (var i = 0; i < tabs.length; i++) if (tabs[i].id === id) return tabs[i]; return tabs[0] }

  function enrich(it) {
    var hasPrice = it.inputPrice !== null && it.inputPrice !== undefined && it.outputPrice !== null && it.outputPrice !== undefined
    it.blended = hasPrice ? (3 * it.inputPrice + it.outputPrice) / 4 : null
    it.value = (it.blended === null || it.score === null) ? null : it.score / Math.max(it.blended, 0.05)
    it.label = it.label || it.name
    it.level = it.level || ""
    return it
  }

  function load(text) {
    try {
      var data = JSON.parse(text)
      var list = (data.items || []).map(enrich)
      items = list
      updated = data.updated || 0
      indexVersion = data.indexVersion || null
      needsKey = !!data.needsKey
      error = data.error || ""
      stale = !!data.stale
      var order = [], seenP = {}, seenL = {}
      for (var i = 0; i < list.length; i++) {
        if (!seenP[list[i].provider]) { seenP[list[i].provider] = true; order.push(list[i].provider) }
        if (list[i].level) seenL[list[i].level] = true
      }
      providers = (data.labs && data.labs.length) ? data.labs : order.slice(0, 6)
      missingLabs = data.missingLabs || []
      levelsPresent = levelOrder.filter(function(l) { return seenL[l] })
      rebuild()
    } catch (e) { error = "Could not read rankings. Press Refresh to retry." }
  }

  function matches(it) {
    if (levelCount > 0 && it.level && !levelSet[it.level]) return false   // models without reasoning modes always stay
    if (labCount > 0 && !(labSet[it.provider] || (labSet["__other"] && providers.indexOf(it.provider) < 0))) return false
    if (minScore > 0 && (it.score === null || it.score < minScore)) return false
    if (pinsOnly && !pins[it.id]) return false
    return true
  }

  // Everything that passes the filters, ranked for one category (no top-N cut, no reverse).
  function ranked(tabId) {
    var out = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!matches(it)) continue
      if (tabId === "cheap" && it.blended === null) continue
      if (tabId === "value" && it.value === null) continue
      if (tabId === "fast" && !it.speed) continue
      if (tabId === "latency" && !it.latency) continue
      out.push(it)
    }
    out.sort(function(a, b) {
      var d = 0
      if (tabId === "cheap") d = a.blended - b.blended
      else if (tabId === "value") d = b.value - a.value
      else if (tabId === "fast") d = b.speed - a.speed
      else if (tabId === "latency") d = a.latency - b.latency
      if (d !== 0) return d
      d = (b.score === null ? -1 : b.score) - (a.score === null ? -1 : a.score)
      return d !== 0 ? d : (a.label < b.label ? -1 : 1)
    })
    return out
  }

  function rebuild() {
    var out = ranked(tab)
    if (reverse) out.reverse()
    matchCount = out.length
    view = limit > 0 ? out.slice(0, limit) : out
    // The chart plots exactly the rows the list shows, so every filter AND the category / top-N apply to it too.
    chartPts = view.filter(function(it) { return it.blended !== null && it.score !== null })
    cmpA = ranked(compareA).slice(0, 5)
    cmpB = ranked(compareB).slice(0, 5)
    cursor = Math.min(cursor, Math.max(0, view.length - 1))
  }

  function savePrefs() {
    var ids = []
    for (var k in pins) if (pins[k]) ids.push(k)
    Quickshell.execDetached(["python3", "-I", "-c", "import sys;open(sys.argv[1],'w').write(sys.argv[2])", prefsPath,
      JSON.stringify({ tab: tab, reverse: reverse, levels: Object.keys(levelSet), labs: Object.keys(labSet), minScore: minScore, pinsOnly: pinsOnly, pins: ids,
                       viewMode: viewMode, compareA: compareA, compareB: compareB, comfortOpen: comfortOpen, readable: readable, zoomStep: zoomStep, simple: simple, limit: limit, stripes: stripes })])
  }
  function loadPrefs(text) {
    try {
      var p = JSON.parse(text)
      if (p.tab) tab = p.tab
      reverse = !!p.reverse
      var ls = {}, bs = {}   // older prefs stored a single level / provider string
      ;(p.levels || (p.level ? [p.level] : [])).forEach(function(k) { ls[k] = true })
      ;(p.labs || (p.provider ? [p.provider] : [])).forEach(function(k) { bs[k] = true })
      levelSet = ls
      labSet = bs
      if (p.minScore !== undefined) minScore = p.minScore
      pinsOnly = !!p.pinsOnly
      var m = {}
      ;(p.pins || []).forEach(function(id) { m[id] = true })
      pins = m
      viewMode = (p.viewMode === "chart" || p.viewMode === "compare") ? p.viewMode : "list"
      if (p.compareA) compareA = p.compareA
      if (p.compareB) compareB = p.compareB
      comfortOpen = !!p.comfortOpen
      readable = !!p.readable
      zoomStep = Math.max(0, Math.min(2, p.zoomStep || 0))
      simple = !!p.simple
      limit = p.limit || 0
      if (p.stripes !== undefined) stripes = !!p.stripes
      rebuild()
    } catch (e) {}
  }
  function apply() { expandedId = ""; rebuild(); savePrefs(); list.positionViewAtBeginning() }
  function choose(name, value) {
    if (name === "tab") { tab = value; reverse = false }
    apply()
  }
  // Multi-select filters: click toggles a value, the "Any"/"All" chip clears the group.
  function toggleSel(name, key) {
    var src = name === "level" ? levelSet : labSet, m = {}
    for (var k in src) m[k] = true
    if (m[key]) delete m[key]; else m[key] = true
    if (name === "level") levelSet = m; else labSet = m
    apply()
  }
  function clearSel(name) { if (name === "level") levelSet = ({}); else labSet = ({}); apply() }
  function sortBy(id) {
    if (tab === id) reverse = !reverse
    else { tab = id; reverse = false }
    apply()
  }
  function cycleMin() { minScore = minSteps[(minSteps.indexOf(minScore) + 1) % minSteps.length]; apply() }
  function cycleLimit() { limit = limitSteps[(limitSteps.indexOf(limit) + 1) % limitSteps.length]; apply() }
  function cycleZoom() { zoomStep = (zoomStep + 1) % 3; savePrefs() }
  function toggle(name) {
    if (name === "readable") readable = !readable
    else if (name === "simple") simple = !simple
    else if (name === "stripes") stripes = !stripes
    else if (name === "pinsOnly") { pinsOnly = !pinsOnly; apply(); return }
    savePrefs()
  }
  function togglePin(it) {
    var m = {}
    for (var k in pins) m[k] = pins[k]
    if (m[it.id]) delete m[it.id]; else m[it.id] = true
    pins = m
    if (pinsOnly) apply(); else savePrefs()
  }
  function setView(mode) { viewMode = mode; savePrefs() }
  function setCompare(which, id) { if (which === "a") compareA = id; else compareB = id; rebuild(); savePrefs() }
  function metricShort(id, m) {
    if (id === "value") return num(m.value, 1) + " IQ/$"
    if (id === "fast") return num(m.speed, 0) + " tok/s"
    if (id === "latency") return m.latency === null ? "—" : num(m.latency, 1) + "s"
    if (id === "cheap") return money(m.blended)
    return "IQ " + iq(m)
  }
  function metricFor(id, m) {
    if (id === "value") return num(m.value, 1) + " IQ per $"
    if (id === "fast") return num(m.speed, 0) + " tok/s"
    if (id === "latency") return num(m.latency, 1) + "s to first token"
    if (id === "cheap") return money(m.blended) + " per 1M tokens"
    return "IQ " + iq(m)
  }
  // Side-by-side rows for the winners of category A and B.
  function compareRows() {
    var a = cmpA.length ? cmpA[0] : null, b = cmpB.length ? cmpB[0] : null
    if (!a || !b) return []
    function pick(av, bv, higher) {
      if (av === null || av === undefined || bv === null || bv === undefined || av === bv) return ""
      return (av > bv) === higher ? "a" : "b"
    }
    function secs(m) { return m.latency === null ? "—" : num(m.latency, 1) + "s" }
    return [
      { m: "IQ (intelligence)", a: iq(a), b: iq(b), win: pick(a.score, b.score, true) },
      { m: "Price per 1M tokens (blended)", a: money(a.blended), b: money(b.blended), win: pick(a.blended, b.blended, false) },
      { m: "Speed (tokens/sec)", a: num(a.speed, 0), b: num(b.speed, 0), win: pick(a.speed, b.speed, true) },
      { m: "Time to first token", a: secs(a), b: secs(b), win: pick(a.latency, b.latency, false) },
      { m: "IQ points per $", a: num(a.value, 1), b: num(b.value, 1), win: pick(a.value, b.value, true) }
    ]
  }
  // One plain-English answer first.
  function verdict() {
    var a = cmpA.length ? cmpA[0] : null, b = cmpB.length ? cmpB[0] : null
    var la = tabInfo(compareA).label, lb = tabInfo(compareB).label
    if (!a || !b) return "No models match your filters for " + (!a ? la : lb) + ". Loosen a filter (Reasoning, Lab or Min IQ)."
    if (a.id === b.id) return la + " and " + lb + " pick the same model: " + a.label + (a.level ? " (" + levelText(a) + ")" : "") + ". No trade-off."
    var rows = compareRows(), wa = 0, wb = 0
    rows.forEach(function(r) { if (r.win === "a") wa++; else if (r.win === "b") wb++ })
    var text = la + " pick (" + a.label + ") wins " + wa + ", " + lb + " pick (" + b.label + ") wins " + wb + " of " + rows.length + " measures."
    if (a.score !== null && b.score !== null && a.score !== b.score && a.blended !== null && b.blended !== null && a.blended !== b.blended) {
      var smart = a.score > b.score ? a : b, cheap = a.blended < b.blended ? a : b
      if (smart.id === cheap.id) text += " " + smart.label + " is both smarter and cheaper."
      else {
        var ratio = smart.blended / cheap.blended
        text += " " + smart.label + " is " + Math.abs(a.score - b.score).toFixed(1) + " IQ points smarter but costs "
              + (cheap.blended <= 0 ? "far more (the other is free)" : (ratio >= 10 ? ratio.toFixed(0) : ratio.toFixed(1)) + "x more per token") + "."
      }
    }
    return text
  }
  function toggleExpand(item) { expandedId = (item && expandedId !== item.id) ? item.id : "" }
  function move(delta) {
    cursor = Math.max(0, Math.min(view.length - 1, cursor + delta))
    list.positionViewAtIndex(cursor, ListView.Contain)
  }
  function showModel(item) {
    viewMode = "list"
    var idx = -1
    for (var i = 0; i < view.length; i++) if (view[i].id === item.id) idx = i
    if (idx < 0) { tab = "smart"; reverse = false; limit = 0; rebuild(); for (var j = 0; j < view.length; j++) if (view[j].id === item.id) idx = j }
    expandedId = item.id
    cursor = Math.max(0, idx)
    savePrefs()
    Qt.callLater(function() { list.positionViewAtIndex(Math.max(0, idx), ListView.Center) })
  }

  // The one cell the active category cares about, used by Simple view and the hero card.
  function keyInfo(m) {
    if (tab === "value") return { h: "IQ / $", v: num(m.value, 1) }
    if (tab === "fast") return { h: "tok/s", v: num(m.speed, 0) }
    if (tab === "latency") return { h: "1st token", v: m.latency === null ? "—" : num(m.latency, 1) + "s" }
    return { h: "Price / 1M", v: money(m.blended) }
  }
  function headerCells() {
    if (simple) return [{ t: "IQ", w: cIq, id: "smart" }, { t: keyInfo({}).h, w: cKey, id: tab === "smart" ? "cheap" : tab }]
    return [{ t: "IQ", w: cIq, id: "smart" }, { t: "In $", w: cMoney, id: "cheap" }, { t: "Out $", w: cMoney, id: "cheap" },
            { t: "tok/s", w: cSpeed, id: "fast" }, { t: "1st tok", w: cLat, id: "latency" }, { t: "IQ/$", w: cValue, id: "value" }]
  }
  function arrow(id) {
    if (tab !== id) return ""
    var desc = (id === "smart" || id === "fast" || id === "value") !== reverse
    return desc ? " ▼" : " ▲"
  }
  function rowCells(m) {
    if (simple) return [{ v: keyInfo(m).v, w: cKey, on: true }]
    return [{ v: money(m.inputPrice), w: cMoney, on: tab === "cheap" }, { v: money(m.outputPrice), w: cMoney, on: tab === "cheap" },
            { v: num(m.speed, 0), w: cSpeed, on: tab === "fast" }, { v: m.latency === null ? "—" : num(m.latency, 1) + "s", w: cLat, on: tab === "latency" },
            { v: num(m.value, 1), w: cValue, on: tab === "value" }]
  }
  function heroMetric(m) { return metricFor(tab, m) }

  // Chip, T and Mascot are shared kit components (Chip.qml, T.qml, Mascot.qml in this folder).

  implicitWidth: toggleButton.implicitWidth
  implicitHeight: toggleButton.implicitHeight

  Process {
    id: fetcher
    command: ["python3", "-I", Qt.resolvedUrl("fetch.py").toString().replace("file://", ""), root.fetchMode]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }
  Process {
    command: ["cat", root.cachePath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length && root.updated === 0) root.load(text) }
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
  Timer { interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh(true) }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = Date.now() }

  WidgetButton {
    id: toggleButton
    bar: root.bar
    text: "LLMs" + (root.old ? " *" : "")
    fontSize: Style.font.caption
    tooltipText: root.view.length ? "Top: " + root.view[0].label + (root.view[0].level ? " (" + root.levelText(root.view[0]) + ")" : "") + " · IQ " + root.iq(root.view[0]) + "\nClick to browse · right-click to refresh"
                 : root.needsKey ? "Free API key needed" : "Fetching rankings…"
    onPressed: function(button) {
      if (button === Qt.RightButton) root.refresh(false)
      else if (root.opened) root.close()
      else {
        if (root.needsKey || root.old || root.error.length > 0) root.refresh(true)
        root.open()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: toggleButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(720 * root.cw))
    contentHeight: panel.fittedContentHeight(Style.space(800), Style.space(940))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.toggleExpand(root.view[root.cursor])
      onMoveRequested: function(dx, dy) { root.move(dy) }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r") root.refresh(false) }

      Column {
        id: controls
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        // ----- title row -----
        Item {
          width: parent.width
          height: Style.space(28) * root.zoom
          T {
            id: title
            ui: root; sz: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
            text: "LLM Leaderboard"
            font.bold: true
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Chip { ui: root; sz: Style.font.caption; label: "List"; active: root.viewMode === "list"; onClicked: root.setView("list") }
            Chip { ui: root; sz: Style.font.caption; label: "Chart"; active: root.viewMode === "chart"; onClicked: root.setView("chart") }
            Chip { ui: root; sz: Style.font.caption; label: "Compare"; active: root.viewMode === "compare"; onClicked: root.setView("compare") }
            Chip { ui: root; sz: Style.font.caption; label: "Comfort"; active: root.comfortOpen; check: true; onClicked: { root.comfortOpen = !root.comfortOpen; root.savePrefs() } }
            Chip {
              ui: root; sz: Style.font.caption
              label: root.needsKey ? "API key setup" : fetcher.running ? "Refreshing…" : "↻ Refresh"
              onClicked: if (root.needsKey) root.setupKey(); else root.refresh(false)
            }
          }
        }

        // ----- comfort (ADHD / dyslexia) -----
        Rectangle {
          visible: root.comfortOpen
          width: parent.width
          height: comfortFlow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: root.fade(0.07)
          Flow {
            id: comfortFlow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)
            Chip { ui: root; sz: Style.font.caption; label: "Readable font"; active: root.readable; check: true; onClicked: root.toggle("readable") }
            Chip { ui: root; sz: Style.font.caption; label: "Text size " + Math.round(root.zoom * 100) + "%"; onClicked: root.cycleZoom() }
            Chip { ui: root; sz: Style.font.caption; label: "Simple view"; active: root.simple; check: true; onClicked: root.toggle("simple") }
            Chip { ui: root; sz: Style.font.caption; label: root.limit ? "Show top " + root.limit : "Show all"; active: root.limit > 0; check: true; onClicked: root.cycleLimit() }
            Chip { ui: root; sz: Style.font.caption; label: "Row stripes + ruler"; active: root.stripes; check: true; onClicked: root.toggle("stripes") }
          }
        }

        // ----- compare pickers: choose two categories -----
        Column {
          visible: root.viewMode === "compare"
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: ["a", "b"]
            delegate: Flow {
              id: pickRow
              required property string modelData
              width: parent.width
              spacing: Style.space(6)
              T { ui: root; sz: Style.font.body; height: Style.spacing.controlHeight * root.zoom; verticalAlignment: Text.AlignVCenter; text: pickRow.modelData.toUpperCase(); font.bold: true; color: Commons.Color.accent }
              Repeater {
                model: root.tabs
                delegate: Chip {
                  required property var modelData
                  ui: root; sz: Style.font.body
                  label: modelData.label
                  active: (pickRow.modelData === "a" ? root.compareA : root.compareB) === modelData.id
                  onClicked: root.setCompare(pickRow.modelData, modelData.id)
                }
              }
            }
          }
        }

        // ----- category tabs -----
        Flow {
          visible: root.viewMode !== "compare"
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.tabs
            delegate: Chip {
              required property var modelData
              ui: root; sz: Style.font.body
              label: modelData.label
              active: root.tab === modelData.id
              onClicked: root.choose("tab", modelData.id)
            }
          }
        }
        T {
          ui: root; sz: Style.font.caption
          width: parent.width
          text: root.viewMode === "compare" ? "Pick two categories. Reasoning, Lab, Min IQ and Pinned below filter both sides." : root.tabInfo(root.tab).about + "  ·  " + root.matchCount + " of " + root.items.length + " models" + (root.minScore === 0 ? " (incl. unscored)" : "") + (root.viewMode === "chart" ? " · plotted: " + root.chartPts.length : "")
          opacity: 0.8
          wrapMode: Text.Wrap
        }

        // ----- reasoning lock -----
        Flow {
          width: parent.width
          spacing: Style.space(6)
          T { ui: root; sz: Style.font.caption; height: Style.space(24) * root.zoom; verticalAlignment: Text.AlignVCenter; text: "Reasoning"; opacity: 0.8 }
          Chip { ui: root; sz: Style.font.caption; label: "Any"; active: root.levelCount === 0; onClicked: root.clearSel("level") }
          Repeater {
            model: root.levelsPresent
            delegate: Chip {
              required property string modelData
              ui: root; sz: Style.font.caption
              label: root.levelLabel[modelData]
              active: !!root.levelSet[modelData]
              check: true
              onClicked: root.toggleSel("level", modelData)
            }
          }
          Chip { ui: root; sz: Style.font.caption; label: root.minScore ? "Min IQ " + root.minScore : "Min IQ: any"; active: root.minScore > 0; onClicked: root.cycleMin() }
          Chip { ui: root; sz: Style.font.caption; label: "★ Pinned"; active: root.pinsOnly; check: true; onClicked: root.toggle("pinsOnly") }
        }

        // ----- lab filter -----
        Flow {
          width: parent.width
          spacing: Style.space(6)
          T { ui: root; sz: Style.font.caption; height: Style.space(24) * root.zoom; verticalAlignment: Text.AlignVCenter; text: "Lab"; opacity: 0.8 }
          Chip { ui: root; sz: Style.font.caption; label: "All"; active: root.labCount === 0; onClicked: root.clearSel("lab") }
          Repeater {
            model: root.providers
            delegate: Chip {
              required property string modelData
              ui: root; sz: Style.font.caption
              label: modelData
              icon: root.mascotUrl(modelData)
              active: !!root.labSet[modelData]
              check: true
              onClicked: root.toggleSel("lab", modelData)
            }
          }
          Chip { ui: root; sz: Style.font.caption; label: "Other labs"; active: !!root.labSet["__other"]; check: true; onClicked: root.toggleSel("lab", "__other") }
        }

        T {
          visible: root.error.length > 0 || root.old || root.missingLabs.length > 0
          ui: root; sz: Style.font.caption
          width: parent.width
          text: root.error || (root.missingLabs.length ? "No models found for " + root.missingLabs.join(", ") + ". Check labs.json." : "Saved rankings · awaiting refresh")
          color: Commons.Color.urgent
          wrapMode: Text.Wrap
        }

        // ----- hero: the answer at a glance -----
        Rectangle {
          id: hero
          readonly property var m: root.view.length ? root.view[0] : null
          visible: root.viewMode === "list" && m !== null && !root.reverse
          width: parent.width
          height: heroRow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
          border.width: 2
          border.color: Commons.Color.accent
          Row {
            id: heroRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            spacing: Style.space(12)
            Mascot { anchors.verticalCenter: parent.verticalCenter; provider: hero.m ? hero.m.provider : ""; px: 40 }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              T { ui: root; sz: Style.font.caption; text: root.tabInfo(root.tab).hero.toUpperCase(); font.bold: true; color: Commons.Color.accent }
              T {
                ui: root; sz: Style.font.title
                text: hero.m ? hero.m.label + (hero.m.level ? "  (" + root.levelText(hero.m) + ")" : "") : ""
                font.bold: true
                width: Math.min(implicitWidth, hero.width - Style.space(90))
                elide: Text.ElideRight
              }
              T {
                ui: root; sz: Style.font.body
                text: hero.m ? root.heroMetric(hero.m) + (root.tab === "smart" ? "" : "   ·   IQ " + root.iq(hero.m)) + "   ·   " + root.money(hero.m.inputPrice) + " in / " + root.money(hero.m.outputPrice) + " out" : ""
                opacity: 0.85
              }
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.cursor = 0; root.expandedId = hero.m.id; list.positionViewAtBeginning() }
          }
        }

        // ----- column headers (click to sort, click again to reverse) -----
        Item {
          visible: root.viewMode === "list"
          width: parent.width
          height: Style.space(20) * root.zoom
          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            height: parent.height
            Repeater {
              model: root.headerCells()
              delegate: Item {
                required property var modelData
                width: modelData.w
                height: parent.height
                T {
                  ui: root; sz: Style.font.caption
                  anchors.fill: parent
                  horizontalAlignment: Text.AlignRight
                  verticalAlignment: Text.AlignVCenter
                  text: modelData.t + root.arrow(modelData.id)
                  color: root.tab === modelData.id ? Commons.Color.accent : root.barForeground
                  opacity: root.tab === modelData.id ? 1 : 0.75
                  font.bold: root.tab === modelData.id
                  elide: Text.ElideLeft
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sortBy(modelData.id) }
              }
            }
          }
        }
      }

      // ----- list view -----
      ListView {
        id: list
        visible: root.viewMode === "list"
        anchors.top: controls.bottom
        anchors.topMargin: Style.space(4)
        anchors.bottom: footer.top
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
          readonly property bool pinned: !!root.pins[modelData.id]
          width: list.width
          height: rowColumn.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: expanded ? root.fade(Style.selectedFillAlpha)
               : hover.containsMouse && root.stripes ? root.fade(Style.hoverFillAlpha * 2)
               : index === root.cursor ? root.fade(Style.selectedFillAlpha * 0.7)
               : hover.containsMouse ? root.fade(Style.hoverFillAlpha)
               : root.stripes && index % 2 === 1 ? root.fade(0.06) : "transparent"
          border.width: expanded ? Style.selectedBorderWidth : 0
          border.color: Commons.Color.accent

          // reading ruler: bold accent bar on the hovered row
          Rectangle {
            visible: root.stripes && hover.containsMouse
            width: 4; radius: 2
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
              height: Math.max(Style.space(38) * root.zoom, root.mascotPx + 6)

              Row {
                id: lead
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Item {   // pin star
                  width: Style.space(24) * root.zoom
                  height: Style.space(30) * root.zoom
                  anchors.verticalCenter: parent.verticalCenter
                  T {
                    ui: root; sz: Style.font.body + 3
                    anchors.centerIn: parent
                    text: row.pinned ? "★" : "☆"
                    color: row.pinned ? Commons.Color.accent : root.barForeground
                    opacity: row.pinned ? 1 : 0.6
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePin(row.modelData) }
                }
                Rectangle {   // rank badge (podium for the top 3)
                  width: Style.space(24) * root.zoom; height: width; radius: Style.cornerRadius
                  anchors.verticalCenter: parent.verticalCenter
                  color: row.index < 3 && !root.reverse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.28) : "transparent"
                  T { ui: root; sz: Style.font.caption; anchors.centerIn: parent; text: row.index + 1; font.bold: row.index < 3 && !root.reverse; opacity: row.index < 3 ? 1 : 0.75 }
                }
                Mascot { anchors.verticalCenter: parent.verticalCenter; provider: row.modelData.provider; px: root.mascotPx }
              }

              Item {
                id: nameCell
                anchors.left: lead.right
                anchors.leftMargin: Style.space(8)
                anchors.right: stats.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                height: nameLine.height + sub.height
                Row {
                  id: nameLine
                  spacing: Style.space(6)
                  T {
                    id: nameText
                    ui: root; sz: Style.font.body
                    width: Math.min(implicitWidth, nameCell.width - (badge.visible ? badge.width + Style.space(6) : 0))
                    text: row.modelData.label
                    elide: Text.ElideRight
                    font.bold: true
                  }
                  Rectangle {
                    id: badge
                    visible: row.modelData.level !== ""
                    anchors.verticalCenter: nameText.verticalCenter
                    width: badgeText.implicitWidth + Style.space(10)
                    height: badgeText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius
                    color: root.fade(0.16)
                    T { id: badgeText; ui: root; sz: Style.font.caption - 1; anchors.centerIn: parent; text: root.levelText(row.modelData) }
                  }
                }
                T {
                  id: sub
                  ui: root; sz: Style.font.caption
                  anchors.top: nameLine.bottom
                  width: parent.width
                  text: row.modelData.provider + (row.modelData.releaseDate ? " · " + row.modelData.releaseDate : "")
                  elide: Text.ElideRight
                  opacity: 0.75
                }
              }

              Row {
                id: stats
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Item {
                  width: root.cIq
                  height: Style.space(32) * root.zoom
                  T {
                    ui: root; sz: Style.font.body
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: root.iq(row.modelData)
                    color: root.tab === "smart" ? Commons.Color.accent : root.barForeground
                    font.bold: root.tab === "smart"
                  }
                  Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4; radius: 2
                    width: parent.width * (row.modelData.score === null ? 0 : Math.min(1, row.modelData.score / 70))
                    color: root.tab === "smart" ? Commons.Color.accent : root.fade(0.5)
                  }
                }
                Repeater {
                  model: root.rowCells(row.modelData)
                  delegate: T {
                    required property var modelData
                    ui: root; sz: Style.font.caption
                    width: modelData.w
                    height: Style.space(32) * root.zoom
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.v
                    color: modelData.on ? Commons.Color.accent : root.barForeground
                    opacity: modelData.on ? 1 : 0.85
                    font.bold: modelData.on
                  }
                }
              }

              MouseArea {
                id: hover
                anchors.fill: parent
                anchors.leftMargin: lead.width + 6
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
                ui: root; sz: Style.font.caption
                width: parent.width
                wrapMode: Text.Wrap
                text: row.modelData.name + "\nInput " + root.money(row.modelData.inputPrice) + " · Output " + root.money(row.modelData.outputPrice)
                      + " per 1M tokens · blended " + root.money(row.modelData.blended) + " (3:1)\n"
                      + root.num(row.modelData.speed, 1) + " tok/s · first token " + root.num(row.modelData.latency, 2) + "s"
                      + (row.modelData.value !== null ? " · " + root.num(row.modelData.value, 1) + " IQ points per $" : "")
                opacity: 0.85
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Chip { ui: root; sz: Style.font.caption; label: row.pinned ? "★ Unpin" : "☆ Pin"; onClicked: root.togglePin(row.modelData) }
                Chip { ui: root; sz: Style.font.caption; label: "Open on Artificial Analysis"; onClicked: root.visit(row.modelData) }
                Chip { ui: root; sz: Style.font.caption; label: "Copy name"; onClicked: root.copyName(row.modelData) }
              }
            }
          }
        }

        T {
          anchors.centerIn: parent
          visible: root.view.length === 0
          width: parent.width * 0.8
          ui: root; sz: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: root.items.length === 0 ? (fetcher.running ? "Fetching the latest leaderboard…" : "No rankings saved yet.")
                : root.pinsOnly ? "Nothing pinned yet. Tap a ☆ on any row to pin it."
                : "No models match these filters. Try Reasoning: Any or a lower Min IQ."
          opacity: 0.7
        }
      }

      // ----- compare view: winners of two categories side by side -----
      Flickable {
        id: cmp
        visible: root.viewMode === "compare"
        anchors.top: controls.bottom
        anchors.topMargin: Style.space(4)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(6)
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: cmpCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: cmpCol
          width: cmp.width
          spacing: Style.space(10)

          Rectangle {   // the answer first
            width: parent.width
            height: verdictText.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
            border.width: 2
            border.color: Commons.Color.accent
            T {
              id: verdictText
              ui: root; sz: Style.font.body
              anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
              wrapMode: Text.Wrap
              font.bold: true
              text: root.verdict()
            }
          }

          Row {   // the two winners
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [{ side: "A", id: root.compareA, rows: root.cmpA }, { side: "B", id: root.compareB, rows: root.cmpB }]
              delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var m: modelData.rows.length ? modelData.rows[0] : null
                width: (cmpCol.width - Style.space(8)) / 2
                height: cardCol.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: root.fade(0.07)
                border.width: 1
                border.color: root.fade(0.5)
                Column {
                  id: cardCol
                  anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
                  spacing: Style.space(5)
                  T { ui: root; sz: Style.font.caption; text: card.modelData.side + " · " + root.tabInfo(card.modelData.id).hero; font.bold: true; color: Commons.Color.accent; width: parent.width; elide: Text.ElideRight }
                  Row {
                    spacing: Style.space(8)
                    Mascot { anchors.verticalCenter: parent.verticalCenter; provider: card.m ? card.m.provider : ""; px: 30 }
                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      T { ui: root; sz: Style.font.body; font.bold: true; width: card.width - Style.space(70); elide: Text.ElideRight
                          text: card.m ? card.m.label + (card.m.level ? "  (" + root.levelText(card.m) + ")" : "") : "No match" }
                      T { ui: root; sz: Style.font.caption; opacity: 0.8; text: card.m ? card.m.provider : "" }
                    }
                  }
                  T { ui: root; sz: Style.font.title; font.bold: true; width: parent.width; elide: Text.ElideRight; text: card.m ? root.metricFor(card.modelData.id, card.m) : "—" }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (card.m) root.showModel(card.m) }
              }
            }
          }

          Column {   // head-to-head table; the better side gets a check mark (not colour alone)
            width: parent.width
            Item {
              width: parent.width
              height: Style.space(24) * root.zoom
              T { ui: root; sz: Style.font.caption; x: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: "Head to head"; opacity: 0.8 }
              T { ui: root; sz: Style.font.caption; font.bold: true; color: Commons.Color.accent; anchors.verticalCenter: parent.verticalCenter; x: parent.width * 0.50; width: parent.width * 0.25; horizontalAlignment: Text.AlignRight; text: "A · " + root.tabInfo(root.compareA).label }
              T { ui: root; sz: Style.font.caption; font.bold: true; color: Commons.Color.accent; anchors.verticalCenter: parent.verticalCenter; x: parent.width * 0.75; width: parent.width * 0.25 - Style.space(8); horizontalAlignment: Text.AlignRight; text: "B · " + root.tabInfo(root.compareB).label }
            }
            Repeater {
              model: root.compareRows()
              delegate: Rectangle {
                id: cmpRow
                required property var modelData
                required property int index
                width: cmpCol.width
                height: Style.space(30) * root.zoom
                color: root.stripes && index % 2 === 1 ? root.fade(0.06) : "transparent"
                T { ui: root; sz: Style.font.caption; x: Style.space(8); anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.48; elide: Text.ElideRight; text: cmpRow.modelData.m; opacity: 0.9 }
                T { ui: root; sz: Style.font.body; anchors.verticalCenter: parent.verticalCenter; x: parent.width * 0.50; width: parent.width * 0.25; horizontalAlignment: Text.AlignRight
                    text: (cmpRow.modelData.win === "a" ? "✓ " : "") + cmpRow.modelData.a
                    font.bold: cmpRow.modelData.win === "a"; color: cmpRow.modelData.win === "a" ? Commons.Color.accent : root.barForeground }
                T { ui: root; sz: Style.font.body; anchors.verticalCenter: parent.verticalCenter; x: parent.width * 0.75; width: parent.width * 0.25 - Style.space(8); horizontalAlignment: Text.AlignRight
                    text: (cmpRow.modelData.win === "b" ? "✓ " : "") + cmpRow.modelData.b
                    font.bold: cmpRow.modelData.win === "b"; color: cmpRow.modelData.win === "b" ? Commons.Color.accent : root.barForeground }
              }
            }
          }

          Row {   // top 5 of each side
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [{ id: root.compareA, rows: root.cmpA }, { id: root.compareB, rows: root.cmpB }]
              delegate: Column {
                id: topCol
                required property var modelData
                width: (cmpCol.width - Style.space(8)) / 2
                spacing: Style.space(2)
                T { ui: root; sz: Style.font.caption; font.bold: true; text: "Top 5 · " + root.tabInfo(topCol.modelData.id).label; opacity: 0.9 }
                Repeater {
                  model: topCol.modelData.rows
                  delegate: Rectangle {
                    id: mini
                    required property var modelData
                    required property int index
                    width: topCol.width
                    height: Math.max(Style.space(30) * root.zoom, 26)
                    radius: Style.cornerRadius
                    color: miniMouse.containsMouse ? root.fade(Style.hoverFillAlpha * 2) : root.stripes && index % 2 === 1 ? root.fade(0.06) : "transparent"
                    Mascot { id: miniMascot; anchors.left: parent.left; anchors.leftMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; provider: mini.modelData.provider; px: 20 }
                    T { id: miniMetric; ui: root; sz: Style.font.caption; anchors.right: parent.right; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter
                        text: root.metricShort(topCol.modelData.id, mini.modelData); font.bold: true; color: Commons.Color.accent }
                    T { ui: root; sz: Style.font.caption; anchors.left: miniMascot.right; anchors.leftMargin: Style.space(6); anchors.right: miniMetric.left; anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: mini.modelData.label + (mini.modelData.level ? " · " + root.levelText(mini.modelData) : "") }
                    MouseArea { id: miniMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showModel(mini.modelData) }
                  }
                }
              }
            }
          }
        }
      }

      // ----- chart view: IQ vs price (follows every filter, the category and top-N) -----
      Canvas {
        id: chart
        visible: root.viewMode === "chart"
        anchors.top: controls.bottom
        anchors.topMargin: Style.space(4)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(6)
        anchors.left: parent.left
        anchors.right: parent.right
        property int hov: -1
        property var spots: []
        onHovChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        Connections {
          target: root
          function onChartPtsChanged() { chart.requestPaint() }
          function onZoomChanged() { chart.requestPaint() }
          function onPinsChanged() { chart.requestPaint() }
          function onBarForegroundChanged() { chart.requestPaint() }
        }

        function geom() {
          var pts = root.chartPts, minP = 1e9, maxP = 0, minS = 1e9, maxS = 0
          for (var i = 0; i < pts.length; i++) {
            var pr = Math.max(pts[i].blended, 0.05)
            minP = Math.min(minP, pr); maxP = Math.max(maxP, pr)
            minS = Math.min(minS, pts[i].score); maxS = Math.max(maxS, pts[i].score)
          }
          if (!pts.length) { minP = 0.1; maxP = 100; minS = 0; maxS = 60 }
          var lx0 = Math.floor(Math.log(minP) / Math.LN10), lx1 = Math.ceil(Math.log(maxP) / Math.LN10)
          if (lx1 <= lx0) lx1 = lx0 + 1
          var y0 = Math.max(0, Math.floor(minS / 5) * 5 - 5), y1 = Math.ceil(maxS / 5) * 5 + 5
          var lpx = Math.round(11 * root.zoom)
          var L = 46 * root.zoom, R = 18, T = 18 + 2 * lpx, B = 54 * root.zoom
          var w = width - L - R, h = height - T - B
          return { lx0: lx0, lx1: lx1, y0: y0, y1: y1, L: L, R: R, T: T, B: B, w: w, h: h,
                   x: function(p) { return L + (Math.log(Math.max(p, 0.05)) / Math.LN10 - lx0) / (lx1 - lx0) * w },
                   y: function(s) { return T + (1 - (s - y0) / (y1 - y0)) * h } }
        }
        function hit(mx, my) {
          var best = -1, bd = 16 * root.zoom
          for (var i = 0; i < spots.length; i++) {
            var d = Math.sqrt(Math.pow(spots[i].x - mx, 2) + Math.pow(spots[i].y - my, 2))
            if (d < bd) { bd = d; best = spots[i].i }
          }
          return best
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var g = geom(), pts = root.chartPts, fg = root.barForeground
          var px = Math.round(11 * root.zoom)
          ctx.font = px + "px \"" + Style.font.family + "\""
          ctx.lineWidth = 1
          // grid + axes
          ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.14)
          ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.7)
          ctx.textAlign = "center"
          for (var d = g.lx0; d <= g.lx1; d++) {
            var gx = g.x(Math.pow(10, d))
            ctx.beginPath(); ctx.moveTo(gx, g.T); ctx.lineTo(gx, g.T + g.h); ctx.stroke()
            ctx.fillText("$" + Math.pow(10, d), gx, g.T + g.h + px + 6)
          }
          ctx.textAlign = "right"
          var step = (g.y1 - g.y0) > 30 ? 10 : 5
          for (var s = Math.ceil(g.y0 / step) * step; s <= g.y1; s += step) {
            var gy = g.y(s)
            ctx.beginPath(); ctx.moveTo(g.L, gy); ctx.lineTo(g.L + g.w, gy); ctx.stroke()
            ctx.fillText(String(s), g.L - 6, gy + px / 3)
          }
          ctx.textAlign = "left"
          ctx.fillText("IQ ↑ smarter", g.L, px + 2)
          // legend: one swatch per lab that is plotted
          var seenLab = {}, legendX = g.L
          for (var li = 0; li < pts.length; li++) {
            var lp = pts[li].provider
            if (seenLab[lp]) continue
            seenLab[lp] = true
            var lw = ctx.measureText(lp).width
            if (legendX + lw + 22 > width - g.R) break
            ctx.fillStyle = root.providerColor(lp); ctx.fillRect(legendX, px * 2 + 2, 9, 9)
            ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.9); ctx.fillText(lp, legendX + 14, px * 2 + 11)
            legendX += lw + 28
          }
          ctx.textAlign = "center"
          ctx.fillText("Price per 1M tokens (blended, log scale) → pricier   ·   top-left = smart and cheap", g.L + g.w / 2, height - 6)

          // best-IQ-for-the-price frontier
          var sorted = pts.slice().sort(function(a, b) { return (a.blended - b.blended) || (b.score - a.score) })
          var front = [], top = -1
          for (var i = 0; i < sorted.length; i++) if (sorted[i].score > top) { front.push(sorted[i]); top = sorted[i].score }
          ctx.strokeStyle = Commons.Color.accent
          ctx.lineWidth = 2
          ctx.beginPath()
          for (var f = 0; f < front.length; f++) {
            var fx = g.x(front[f].blended), fy = g.y(front[f].score)
            if (f === 0) ctx.moveTo(fx, fy); else ctx.lineTo(fx, fy)
          }
          ctx.stroke()

          // dots
          var spotList = []
          for (var k = 0; k < pts.length; k++) {
            var cx = g.x(pts[k].blended), cy = g.y(pts[k].score)
            spotList.push({ x: cx, y: cy, i: k })
            ctx.fillStyle = root.providerColor(pts[k].provider)
            ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.6)
            ctx.lineWidth = 1
            ctx.fillRect(cx - 4, cy - 4, 8, 8)       // square "pixels" to match the mascots
            ctx.strokeRect(cx - 4, cy - 4, 8, 8)
            if (root.pins[pts[k].id]) {
              ctx.strokeStyle = Commons.Color.accent; ctx.lineWidth = 2
              ctx.strokeRect(cx - 7, cy - 7, 14, 14)
            }
          }
          spots = spotList

          // winner of the category: one per selected lab when comparing labs, else the overall best
          var bests = [], seenBest = {}
          if (!root.reverse && root.labCount > 1) {
            for (var bi = 0; bi < pts.length; bi++) if (!seenBest[pts[bi].provider]) { seenBest[pts[bi].provider] = true; bests.push(pts[bi]) }
          } else if (!root.reverse && pts.length) bests.push(pts[0])
          for (var q = 0; q < bests.length; q++) {
            var wx = g.x(bests[q].blended), wy = g.y(bests[q].score)
            ctx.strokeStyle = Commons.Color.accent; ctx.lineWidth = 3
            ctx.strokeRect(wx - 9, wy - 9, 18, 18)
            ctx.fillStyle = Commons.Color.accent; ctx.textAlign = "left"
            ctx.fillText("#1 " + (root.labCount > 1 ? bests[q].provider : root.tabInfo(root.tab).label), wx + 13, wy + 4)
          }
          // what is being plotted
          ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.85); ctx.textAlign = "right"
          ctx.fillText(root.tabInfo(root.tab).label + " · " + pts.length + " models" + (root.limit ? " (top " + root.limit + ")" : ""), width - g.R, px + 2)

          // frontier labels (the sweet spots)
          ctx.fillStyle = fg
          ctx.lineWidth = 1
          for (var j = 0; j < front.length; j++) {
            var lx = g.x(front[j].blended), ly = g.y(front[j].score)
            var txt = front[j].label + (front[j].level ? " " + root.levelText(front[j]) : "")
            var tw = ctx.measureText(txt).width
            ctx.textAlign = (lx + tw + 12 > width - g.R) ? "right" : "left"
            ctx.fillText(txt, ctx.textAlign === "left" ? lx + 9 : lx - 9, ly + (j % 2 === 0 ? -8 : 15))
          }

          // hover tooltip
          if (hov >= 0 && hov < pts.length) {
            var p = pts[hov], hx = g.x(p.blended), hy = g.y(p.score)
            ctx.strokeStyle = Commons.Color.accent; ctx.lineWidth = 2
            ctx.strokeRect(hx - 8, hy - 8, 16, 16)
            var tip = p.label + (p.level ? " (" + root.levelText(p) + ")" : "") + "  ·  " + p.provider + "  ·  IQ " + p.score + "  ·  " + root.money(p.blended) + " blended"
            ctx.textAlign = "left"
            var bw = ctx.measureText(tip).width + 16, bh = px + 12
            var bx = Math.max(g.L, Math.min(width - bw - 4, hx - bw / 2)), by = hy > g.T + bh + 24 ? hy - bh - 14 : hy + 14
            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.88)
            ctx.fillRect(bx, by, bw, bh)
            ctx.strokeStyle = Commons.Color.accent; ctx.lineWidth = 1
            ctx.strokeRect(bx, by, bw, bh)
            ctx.fillStyle = "#ffffff"
            ctx.fillText(tip, bx + 8, by + px + 3)
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: chart.hov >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
          onPositionChanged: function(m) { chart.hov = chart.hit(m.x, m.y) }
          onExited: chart.hov = -1
          onClicked: function(m) { var i = chart.hit(m.x, m.y); if (i >= 0) root.showModel(root.chartPts[i]) }
        }
        T {
          anchors.centerIn: parent
          visible: root.chartPts.length === 0
          ui: root; sz: Style.font.body
          text: "No plottable models match these filters. Loosen Reasoning, Lab or Min IQ."
          opacity: 0.7
        }
      }

      T {
        id: footer
        ui: root; sz: Style.font.caption
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        text: "artificialanalysis.ai · " + root.items.length + " models · Intelligence Index" + (root.indexVersion ? " v" + root.indexVersion : "")
              + " · USD per 1M tokens" + (root.updated ? " · updated " + new Date(root.updated * 1000).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "")
        elide: Text.ElideRight
        opacity: 0.7
      }
    }
  }
}
