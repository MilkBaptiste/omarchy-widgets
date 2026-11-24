import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Projects: milk-style tracker panel. Data = snapshot of the Claude "Malik — Project Tracker" artifact
// (~/.cache/milk-project-tracker/projects.json). Your edits, ticks, notes and the Today queue are
// saved locally in state.json beside it, and survive snapshot refreshes (see README.md).
Panel {
  id: root
  moduleName: "milk.project-tracker"

  // ---- comfort (ADHD / dyslexia) ----
  property bool readable: false
  property int zoomStep: 0
  property bool comfortOpen: false
  property string readFamily: "Noto Sans"
  readonly property real zoom: [1, 1.15, 1.3][zoomStep]
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/milk-project-tracker"
  readonly property string prefsPath: cacheDir + "/prefs.json"
  readonly property string dataPath: cacheDir + "/projects.json"
  readonly property string statePath: cacheDir + "/state.json"
  property int typing: 0     // number of focused text boxes: pauses panel shortcut keys

  function fade(alpha) { return Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, alpha) }
  function writeFile(path, obj) {
    Quickshell.execDetached(["python3", "-I", "-c",
      "import os,sys;os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True);open(sys.argv[1],'w').write(sys.argv[2])",
      path, JSON.stringify(obj)])
  }
  function savePrefs() { writeFile(prefsPath, { readable: readable, zoomStep: zoomStep, comfortOpen: comfortOpen, simple: simple }) }
  function loadPrefs(text) {
    try {
      var p = JSON.parse(text)
      readable = !!p.readable
      zoomStep = Math.max(0, Math.min(2, p.zoomStep || 0))
      comfortOpen = !!p.comfortOpen
      simple = !!p.simple
    } catch (e) {}
  }

  // ---- data ----
  property var db: ({ projects: [], tiers: [], upcoming: [], links: {}, headline: "", runway: "", generated: "" })
  property var st: ({ edits: {}, notes: [], today: [] })
  property bool simple: false           // Simple view: hide the Coming-up card and the status bar
  property var tierSel: ({})
  property var healthSel: ({})
  property string expanded: ""
  property string editRef: ""
  property var draft: ({})
  property string noteRef: ""
  property bool todayOpen: false
  property var rows: []
  readonly property var healthLabel: ({ moving: "Moving", stuck: "Stuck", parked: "Parked", "new": "New", dead: "Dead", done: "Done" })
  readonly property var healthMark: ({ moving: "▶", stuck: "!", parked: "‖", "new": "+", dead: "×", done: "✓" })
  readonly property var stageName: ["Idea", "Planned", "Building", "Live", "Earning"]
  readonly property var tierShort: ({ money: "Money", engine: "Engine", bet: "Bets", garage: "Garage", dead: "Graveyard" })

  function loadData(text) { try { db = JSON.parse(text) } catch (e) {} }
  function loadState(text) {
    try { var s = JSON.parse(text); st = { edits: s.edits || {}, notes: s.notes || [], today: s.today || [] } } catch (e) {}
  }
  function saveState() { st = { edits: st.edits, notes: st.notes, today: st.today }; writeFile(statePath, st) }

  // your edits win until the snapshot itself changes that field
  function merged(p) {
    var q = Object.assign({}, p); q._edited = false; q._done = false
    var e = st.edits[p.ref]
    if (e) {
      var b = e.base || {}, keys = ["now", "next", "health", "stage"]
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i]
        if (e[k] !== undefined && String(b[k]) === String(p[k])) { q[k] = e[k]; q._edited = true }
      }
      if (e.nextDone && e.nextDoneFor === q.next) q._done = true
    }
    return q
  }
  function recompute() {
    var out = [], ts = Object.keys(tierSel).length, hs = Object.keys(healthSel).length, l = db.projects || []
    for (var i = 0; i < l.length; i++) {
      var q = merged(l[i])
      if (ts ? !tierSel[q.tier] : q.tier === "dead") continue
      if (hs && !healthSel[q.health]) continue
      out.push(q)
    }
    rows = out
  }
  onDbChanged: recompute()
  onStChanged: recompute()
  onTierSelChanged: recompute()
  onHealthSelChanged: recompute()

  function daysLeft() {
    if (!db.runway) return 0
    var a = db.runway.split("-"), g = (db.generated || db.runway).split("-")
    return Math.max(0, Math.round((new Date(a[0], a[1] - 1, a[2]) - new Date(g[0], g[1] - 1, g[2])) / 864e5))
  }
  function toggleSet(which, key) {
    var s = Object.assign({}, which === "tier" ? tierSel : healthSel)
    if (s[key]) delete s[key]; else s[key] = true
    if (which === "tier") tierSel = s; else healthSel = s
  }
  function count(h) { var n = 0, l = db.projects || []; for (var i = 0; i < l.length; i++) { var q = merged(l[i]); if (q.health === h && q.tier !== "dead") n++ } return n }
  function tierColor(id) { var t = db.tiers || []; for (var i = 0; i < t.length; i++) if (t[i].id === id) return t[i].color; return "#888888" }
  function notesFor(ref) { return st.notes.filter(function(n) { return n.ref === ref }) }
  function dayStr(ms) { return Qt.formatDate(new Date(ms), "MMM d") }

  // ---- actions ----
  function patchEdit(p, fields) {
    var edits = Object.assign({}, st.edits), e = Object.assign({}, edits[p.ref] || {})
    if (!e.base) e.base = { now: p.now, next: p.next, health: p.health, stage: p.stage }
    for (var k in fields) e[k] = fields[k]
    edits[p.ref] = e; st.edits = edits; saveState()
  }
  function setDone(q, done) { patchEdit(q, { nextDone: done, nextDoneFor: q.next }) }
  function openEdit(q) { draft = { now: q.now, next: q.next, health: q.health, stage: q.stage }; editRef = q.ref; noteRef = "" }
  function saveEditForm(q) {
    var base = (db.projects || []).filter(function(x) { return x.ref === q.ref })[0]
    var e = { base: { now: base.now, next: base.next, health: base.health, stage: base.stage }, updated: Date.now() }
    var old = st.edits[q.ref]
    ;["now", "next", "health", "stage"].forEach(function(k) { if (String(draft[k]) !== String(base[k])) e[k] = draft[k] })
    if (old && old.nextDone && old.nextDoneFor === (e.next !== undefined ? e.next : base.next)) { e.nextDone = true; e.nextDoneFor = old.nextDoneFor }
    var edits = Object.assign({}, st.edits)
    if (e.now === undefined && e.next === undefined && e.health === undefined && e.stage === undefined && !e.nextDone) delete edits[q.ref]; else edits[q.ref] = e
    st.edits = edits; saveState(); editRef = ""
  }
  function undoEdits(q) { var edits = Object.assign({}, st.edits); delete edits[q.ref]; st.edits = edits; saveState(); editRef = "" }
  function addNote(ref, text) {
    text = text.trim(); if (!text) return
    st.notes = st.notes.concat([{ ref: ref, text: text.slice(0, 4000), created: Date.now() }]); saveState(); noteRef = ""
  }
  function delNote(n) { st.notes = st.notes.filter(function(x) { return x !== n && x.created !== n.created }); saveState() }
  function addToday(text, ref) {
    text = (text || "").trim(); if (!text) return
    st.today = st.today.concat([{ text: text.slice(0, 500), ref: ref || "", created: Date.now() }]); saveState()
  }
  function delToday(it) { st.today = st.today.filter(function(x) { return x.created !== it.created }); saveState() }
  function startSession(q) {
    var prompt = "Project " + q.ref + " (" + q.name + "). Now: " + q.now + " Next step: " + q.next +
      " Let's work on this next step together. Start by confirming what you understand and what you need from me."
    Quickshell.execDetached(["omarchy-launch-tui", "claude", prompt]); root.close()
  }
  function openLink(url) { Quickshell.execDetached(["xdg-open", url]) }

  Process {
    id: dataProc
    command: ["cat", root.dataPath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length) root.loadData(text) }
  }
  Process {
    id: stateProc
    command: ["cat", root.statePath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length) root.loadState(text) }
  }
  onOpenedChanged: if (opened) { dataProc.running = true; stateProc.running = true }

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

  implicitWidth: toggleButton.implicitWidth
  implicitHeight: toggleButton.implicitHeight

  WidgetButton {
    id: toggleButton
    bar: root.bar
    text: "Projects"
    fontSize: Style.font.caption
    tooltipText: root.count("stuck") + " stuck, " + root.count("moving") + " moving, " + root.daysLeft() + " days to runway"
    onPressed: function(button) { if (root.opened) root.close(); else root.open() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: toggleButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(620 * root.zoom))
    contentHeight: panel.fittedContentHeight(Style.space(700), Style.space(860))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.typing > 0
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: col
        anchors.fill: parent
        spacing: Style.space(8)

        Item {   // title row
          width: parent.width
          height: Style.spacing.controlHeight * root.zoom
          T { ui: root; sz: Style.font.title; anchors.verticalCenter: parent.verticalCenter; text: "Project Tracker"; font.bold: true }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Chip { ui: root; label: "Today " + root.st.today.length; active: root.todayOpen; check: true; onClicked: root.todayOpen = !root.todayOpen }
            Chip { ui: root; label: "Reload"; onClicked: { dataProc.running = true; stateProc.running = true } }
            Chip { ui: root; label: "Comfort"; active: root.comfortOpen; check: true; onClicked: { root.comfortOpen = !root.comfortOpen; root.savePrefs() } }
          }
        }

        Rectangle {   // comfort panel
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
            Chip { ui: root; label: "Readable font"; active: root.readable; check: true; onClicked: { root.readable = !root.readable; root.savePrefs() } }
            Chip { ui: root; label: "Text size " + Math.round(root.zoom * 100) + "%"; onClicked: { root.zoomStep = (root.zoomStep + 1) % 3; root.savePrefs() } }
            Chip { ui: root; label: "Simple view"; active: root.simple; check: true; onClicked: { root.simple = !root.simple; root.savePrefs() } }
          }
        }

        Rectangle {   // Today queue (opened from the title row)
          visible: root.todayOpen
          width: parent.width
          height: todayCol.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: root.fade(0.07)
          border.width: 1; border.color: root.fade(0.5)
          antialiasing: false
          Column {
            id: todayCol
            anchors.fill: parent; anchors.margins: Style.space(10)
            spacing: Style.space(6)
            T { ui: root; font.bold: true; text: "Sending to Today" }
            T { visible: root.st.today.length === 0; ui: root; sz: Style.font.caption; opacity: 0.8; width: parent.width; wrapMode: Text.Wrap; text: "Nothing waiting. Use “+ Today” on a project, or type below." }
            Repeater {
              model: root.st.today
              Item {
                required property var modelData
                width: todayCol.width; height: Math.max(tt.implicitHeight, Style.space(24))
                T { id: tt; ui: root; sz: Style.font.caption; width: parent.width - Style.space(30); wrapMode: Text.Wrap
                    text: (modelData.ref ? modelData.ref + "  " : "") + modelData.text }
                Chip { ui: root; sz: Style.font.caption; label: "×"; anchors.right: parent.right; onClicked: root.delToday(modelData) }
              }
            }
            Field { id: todayIn; ui: root; width: parent.width; placeholder: "Send something to Today… (Enter)"
              onAccepted: { root.addToday(text, ""); text = "" }
              onEscaped: focus = false }
            Flow {
              width: parent.width; spacing: Style.space(6)
              Repeater {
                model: Object.keys(root.db.links || {})
                Chip { required property string modelData; ui: root; sz: Style.font.caption; label: modelData + " ↗"; onClicked: root.openLink(root.db.links[modelData]) }
              }
            }
          }
        }

        Rectangle {   // hero: the blunt answer + runway
          width: parent.width
          height: heroRow.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: root.fade(0.07)
          border.width: 2
          border.color: Commons.Color.accent
          antialiasing: false
          Row {
            id: heroRow
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)
            Column {
              width: Style.space(96 * root.zoom)
              T { ui: root; sz: Style.font.title * 1.8; text: String(root.daysLeft()); font.bold: true; color: Commons.Color.accent }
              T { ui: root; sz: Style.font.caption; text: "days to " + (root.db.runway || "?"); opacity: 0.8; width: parent.width; wrapMode: Text.Wrap }
            }
            T { ui: root; width: parent.width - Style.space(96 * root.zoom) - Style.space(12); wrapMode: Text.Wrap; text: root.db.headline || "No data yet. Is " + root.dataPath + " there?" }
          }
        }

        Rectangle {   // coming up (hidden in Simple view)
          visible: !root.simple && (root.db.upcoming || []).length > 0
          width: parent.width
          height: visible ? upCol.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: root.fade(0.04)
          border.width: 1; border.color: root.fade(0.3)
          antialiasing: false
          Column {
            id: upCol
            anchors.fill: parent; anchors.margins: Style.space(8)
            spacing: Style.space(3)
            T { ui: root; sz: Style.font.caption; font.bold: true; text: "Coming up" }
            Repeater {
              model: (root.db.upcoming || []).slice(0, 3)
              Item {
                required property var modelData
                width: upCol.width; height: Math.max(wT.implicitHeight, bT.implicitHeight)
                T { id: wT; ui: root; sz: Style.font.caption; font.bold: true; width: parent.width * 0.3; wrapMode: Text.Wrap; text: modelData.when }
                T { id: bT; ui: root; sz: Style.font.caption; x: parent.width * 0.32; width: parent.width * 0.68; wrapMode: Text.Wrap; text: modelData.what + " — " + modelData.why; opacity: 0.9 }
              }
            }
          }
        }

        Row {   // status bar (hidden in Simple view); counts are also in the chips below
          visible: !root.simple
          width: parent.width; height: visible ? Style.space(8) : 0
          Repeater {
            model: ["moving", "new", "parked", "stuck"]
            Rectangle {
              required property string modelData
              readonly property int n: root.count(modelData)
              width: n * (col.width / Math.max(1, root.count("moving") + root.count("new") + root.count("parked") + root.count("stuck")))
              height: parent.height; antialiasing: false
              color: modelData === "stuck" ? Commons.Color.urgent : modelData === "moving" ? Commons.Color.accent
                   : modelData === "new" ? root.fade(0.6) : root.fade(0.3)
            }
          }
        }

        Flow {   // status filters (multi-select)
          width: parent.width
          spacing: Style.space(6)
          Chip { ui: root; label: "Any status"; active: Object.keys(root.healthSel).length === 0; check: true; onClicked: root.healthSel = ({}) }
          Repeater {
            model: ["moving", "stuck", "parked", "new", "done"]
            Chip {
              required property string modelData
              ui: root
              label: root.healthMark[modelData] + " " + root.healthLabel[modelData] + " " + root.count(modelData)
              active: !!root.healthSel[modelData]
              check: true
              onClicked: root.toggleSet("health", modelData)
            }
          }
        }
        Flow {   // group filters (multi-select)
          width: parent.width
          spacing: Style.space(6)
          Chip { ui: root; label: "Any group"; active: Object.keys(root.tierSel).length === 0; check: true; onClicked: root.tierSel = ({}) }
          Repeater {
            model: root.db.tiers || []
            Chip {
              required property var modelData
              ui: root
              label: root.tierShort[modelData.id] || modelData.id
              active: !!root.tierSel[modelData.id]
              check: true
              onClicked: root.toggleSet("tier", modelData.id)
            }
          }
        }

        Flickable {
          id: scroller
          width: parent.width
          height: col.height - y
          contentHeight: list.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: list
            width: scroller.width
            spacing: Style.space(4)

            Repeater {
              model: root.rows
              Rectangle {
                id: card
                required property var modelData
                readonly property bool open: root.expanded === modelData.ref
                width: list.width
                height: cardCol.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                antialiasing: false
                color: open ? root.fade(0.10) : hover.containsMouse ? root.fade(0.08) : root.fade(0.04)
                border.width: open ? 2 : 1
                border.color: open ? Commons.Color.accent : root.fade(0.3)

                Rectangle { width: Style.space(4); height: parent.height; color: root.tierColor(modelData.tier) }
                MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.expanded = card.open ? "" : modelData.ref }

                Column {
                  id: cardCol
                  anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                  anchors.leftMargin: Style.space(14); anchors.rightMargin: Style.space(10); anchors.topMargin: Style.space(7)
                  spacing: Style.space(5)

                  Item {
                    width: parent.width
                    height: nameT.implicitHeight
                    T { id: nameT; ui: root; text: modelData.ref + "  " + modelData.name + (modelData._edited ? "  (edited)" : ""); font.bold: true
                        width: parent.width - statusT.implicitWidth - Style.space(10); elide: Text.ElideRight }
                    T { id: statusT; ui: root; anchors.right: parent.right; sz: Style.font.caption; font.bold: true
                        text: root.healthMark[modelData.health] + " " + root.healthLabel[modelData.health]
                        color: modelData.health === "stuck" ? Commons.Color.urgent : root.barForeground }
                  }
                  T { ui: root; sz: Style.font.caption; opacity: modelData._done ? 0.6 : 0.85; width: parent.width; wrapMode: Text.Wrap
                      font.strikeout: modelData._done
                      text: (modelData._done ? "✓ Done: " : "Next: ") + modelData.next; maximumLineCount: card.open ? 99 : 2; elide: Text.ElideRight }

                  // ---- details (click the row) ----
                  Column {
                    visible: card.open
                    width: parent.width
                    spacing: Style.space(5)
                    T { ui: root; sz: Style.font.caption; width: parent.width; wrapMode: Text.Wrap; text: "Now: " + modelData.now }
                    T { visible: !!modelData.signal; ui: root; sz: Style.font.caption; width: parent.width; wrapMode: Text.Wrap; font.bold: true; text: "News: " + (modelData.signal || "") }
                    T { ui: root; sz: Style.font.caption; opacity: 0.75; text: "Stage: " + root.stageName[modelData.stage] + "  ·  last touched " + modelData.last }

                    Column {   // notes
                      width: parent.width
                      spacing: Style.space(3)
                      Repeater {
                        model: root.notesFor(modelData.ref)
                        Item {
                          required property var modelData
                          width: parent.width; height: Math.max(nt.implicitHeight, Style.space(22))
                          T { id: nt; ui: root; sz: Style.font.caption; width: parent.width - Style.space(30); wrapMode: Text.Wrap; text: root.dayStr(modelData.created) + "  " + modelData.text }
                          Chip { ui: root; sz: Style.font.caption; label: "×"; anchors.right: parent.right; onClicked: root.delNote(modelData) }
                        }
                      }
                    }

                    Flow {   // actions
                      visible: root.editRef !== modelData.ref && root.noteRef !== modelData.ref
                      width: parent.width
                      spacing: Style.space(6)
                      Chip { visible: modelData.health !== "dead" && modelData.health !== "done"; ui: root; sz: Style.font.caption; label: "▶ Start"; onClicked: root.startSession(modelData) }
                      Chip { visible: modelData.health !== "dead"; ui: root; sz: Style.font.caption; label: "Next step done"; active: modelData._done; check: true; onClicked: root.setDone(modelData, !modelData._done) }
                      Chip { visible: modelData.health !== "dead" && modelData.health !== "done"; ui: root; sz: Style.font.caption; label: "+ Today"; onClicked: root.addToday(modelData.name + ": " + modelData.next, modelData.ref) }
                      Chip { ui: root; sz: Style.font.caption; label: "+ Note"; onClicked: { root.noteRef = modelData.ref; root.editRef = "" } }
                      Chip { ui: root; sz: Style.font.caption; label: "Edit"; onClicked: root.openEdit(modelData) }
                    }

                    Column {   // note form
                      visible: root.noteRef === modelData.ref
                      width: parent.width
                      spacing: Style.space(5)
                      Field { id: noteIn; ui: root; width: parent.width; placeholder: "Your note… (Enter saves)"
                        onAccepted: root.addNote(modelData.ref, text)
                        onEscaped: root.noteRef = ""
                        Component.onCompleted: if (visible) grab() }
                      Row { spacing: Style.space(6)
                        Chip { ui: root; sz: Style.font.caption; label: "Save note"; active: true; onClicked: root.addNote(modelData.ref, noteIn.text) }
                        Chip { ui: root; sz: Style.font.caption; label: "Cancel"; onClicked: root.noteRef = "" } }
                    }

                    Loader {   // edit form
                      active: root.editRef === modelData.ref
                      width: parent.width
                      sourceComponent: Column {
                        spacing: Style.space(5)
                        T { ui: root; sz: Style.font.caption; font.bold: true; text: "Status" }
                        Flow { width: parent.width; spacing: Style.space(6)
                          Repeater { model: ["moving", "stuck", "parked", "new", "done", "dead"]
                            Chip { required property string modelData; ui: root; sz: Style.font.caption; check: true
                              label: root.healthMark[modelData] + " " + root.healthLabel[modelData]; active: root.draft.health === modelData
                              onClicked: { var d = Object.assign({}, root.draft); d.health = modelData; root.draft = d } } } }
                        T { ui: root; sz: Style.font.caption; font.bold: true; text: "Stage" }
                        Flow { width: parent.width; spacing: Style.space(6)
                          Repeater { model: root.stageName
                            Chip { required property string modelData; required property int index; ui: root; sz: Style.font.caption; check: true
                              label: modelData; active: root.draft.stage === index
                              onClicked: { var d = Object.assign({}, root.draft); d.stage = index; root.draft = d } } } }
                        T { ui: root; sz: Style.font.caption; font.bold: true; text: "Now" }
                        Field { ui: root; width: parent.width; lines: 3; text: root.draft.now; onTextChanged: root.draft.now = text; onEscaped: root.editRef = "" }
                        T { ui: root; sz: Style.font.caption; font.bold: true; text: "Next" }
                        Field { ui: root; width: parent.width; lines: 3; text: root.draft.next; onTextChanged: root.draft.next = text; onEscaped: root.editRef = "" }
                        Row { spacing: Style.space(6)
                          Chip { ui: root; sz: Style.font.caption; label: "Save"; active: true; onClicked: root.saveEditForm(card.modelData) }
                          Chip { ui: root; sz: Style.font.caption; label: "Cancel"; onClicked: root.editRef = "" }
                          Chip { visible: !!root.st.edits[card.modelData.ref]; ui: root; sz: Style.font.caption; label: "Undo my edits"; onClicked: root.undoEdits(card.modelData) } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
