import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Telegram: one card per agent chat in the "Hermes" Telegram folder, newest message first.
// Click a card -> opens that chat in Telegram Desktop. Refresh re-reads everything.
// Live: tg.py daemon keeps a read-only connection and pushes a snapshot on every change.
Panel {
  id: root
  moduleName: "milk.telegram"

  // ---------- data ----------
  property var chats: []
  property string folderName: "Hermes"
  property string problem: ""          // "", needs_login, no_folder, offline
  property var otherFolders: []
  property double updated: 0
  property double now: Date.now()
  property bool live: false
  property var current: null           // chat open on the chat screen, or null = agent list
  property var messages: []
  property string sendError: ""
  // voice: playing messages + dictating (speech-to-text runs locally through voxtype)
  property string playingKey: ""       // "chat:msg" currently playing
  property string loadingKey: ""
  property string playPath: ""
  property string dictState: ""        // "", listening, transcribing
  property string dictHint: ""
  property bool dictReleased: false
  property bool dictLatched: false      // quick tap = keep listening until the next tap (no need to hold)
  property double pressAt: 0
  property double dictStart: 0
  property bool autoSend: false
  readonly property string recPath: Quickshell.env("HOME") + "/.cache/milk-telegram/dictation.wav"
  function vkey(chatId, mid) { return chatId + ":" + mid }
  function togglePlay(chatId, mid) {
    var k = vkey(chatId, mid)
    var wasPlaying = playingKey === k
    player.running = false
    playingKey = ""
    loadingKey = ""
    if (wasPlaying) return
    loadingKey = k
    cmd({ cmd: "audio", id: chatId, msg: mid })
  }
  function startDictation() {
    player.running = false; playingKey = ""
    dictLatched = false
    dictHint = ""; dictReleased = false; dictStart = Date.now(); dictState = "listening"
    pauser.running = true      // pause music/video first so it doesn't leak into the mic, then record
  }
  function dictPress() {
    if (dictState === "listening" && dictLatched) { stopDictation(); return }   // second tap ends a latched recording
    if (dictState !== "") return
    pressAt = Date.now()
    startDictation()
  }
  function dictRelease() {
    if (dictState !== "listening" || dictLatched) return
    if (Date.now() - pressAt < 450) { dictLatched = true; dictHint = "Listening. Tap the button again when you're done."; return }   // a quick tap latches
    stopDictation()
  }
  function stopDictation() {
    if (dictState !== "listening") return
    dictLatched = false
    dictReleased = true
    if (recorder.running) recorder.signal(2)   // SIGINT lets pw-record finish the wav file
  }
  function dictDone(text) {
    dictState = ""
    var t = String(text).trim()
    if (!t || t === "__SILENT__") { dictHint = "Didn't catch anything. Hold the button while you speak."; return }
    composer.text = (composer.text.trim() ? composer.text.trim() + " " : "") + t
    if (autoSend && send(composer.text)) composer.text = ""
    composer.forceActiveFocus()
  }
  property string pending: ""          // message just sent, shown dimmed until Telegram confirms it
  property var typingAt: ({})          // chat id -> ms timestamp of the last "typing" signal
  property double tick: Date.now()
  property int phase: 0
  readonly property var shown: pending ? messages.concat([{ id: -1, out: true, pending: true, text: pending, date: 0 }]) : messages
  function isTyping(c) { return !!c && typingAt[c.id] !== undefined && tick - typingAt[c.id] < 7000 }
  readonly property bool anyTyping: { var k = tick; for (var id in typingAt) if (k - typingAt[id] < 7000) return true; return false }
  readonly property int unreadTotal: { var n = 0; for (var i = 0; i < chats.length; i++) n += chats[i].unread; return n }
  readonly property int unreadChats: { var n = 0; for (var i = 0; i < chats.length; i++) if (chats[i].unread > 0) n++; return n }

  // ---------- comfort (ADHD / dyslexia) ----------
  readonly property bool readable: true   // Readable font is the default (no option)
  property int zoomPct: 100            // 80 / 90 / 100 / 115 / 130
  readonly property var zoomSteps: [80, 90, 100, 115, 130]
  property bool comfortOpen: false
  property bool simple: false           // one-line previews
  property string readFamily: "Noto Sans"
  readonly property real zoom: zoomPct / 100
  readonly property string prefsPath: Quickshell.env("HOME") + "/.cache/milk-telegram/prefs.json"
  readonly property string cachePath: Quickshell.env("HOME") + "/.cache/milk-telegram/state.json"
  readonly property string tgScript: Qt.resolvedUrl("tg.py").toString().replace("file://", "")
  readonly property string py: Quickshell.env("HOME") + "/.local/share/milk-telegram/venv/bin/python"

  // opaque card fill: theme background with a foreground tint, so nothing behind the panel shows through
  function solid(a) { var b = Commons.Color.background, f = root.barForeground; return Qt.rgba(b.r + (f.r - b.r) * a, b.g + (f.g - b.g) * a, b.b + (f.b - b.b) * a, 1) }
  function fade(alpha) { return Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, alpha) }
  function savePrefs() {
    Quickshell.execDetached(["python3", "-I", "-c",
      "import os,sys;os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True);open(sys.argv[1],'w').write(sys.argv[2])",
      prefsPath, JSON.stringify({ autoSend: autoSend, zoomPct: zoomPct, comfortOpen: comfortOpen, simple: simple })])
  }
  function loadPrefs(text) {
    try {
      var p = JSON.parse(text)
      if (zoomSteps.indexOf(p.zoomPct) >= 0) zoomPct = p.zoomPct
      else if (p.zoomStep !== undefined) zoomPct = [100, 115, 130][p.zoomStep] || 100   // older saved setting
      comfortOpen = !!p.comfortOpen
      autoSend = !!p.autoSend
      simple = !!p.simple
    } catch (e) {}
  }

  property var emojiMap: ({})
  readonly property var emojiPool: ["🦊","🐙","🦉","🐢","🦄","🐝","🦀","🐸","🍄","🌵","🔮","🚀","🎲","🧩","🔥","🌊"]
  // saved emoji for the chat id; a new bot gets the first pool emoji nobody uses (stable until you add it to emojis.json)
  function emojiFor(c) {
    var key = String(c.id)
    if (emojiMap[key]) return emojiMap[key]
    var used = {}
    for (var k in emojiMap) used[emojiMap[k]] = true
    var start = Math.abs(Number(key) % emojiPool.length)
    for (var i = 0; i < emojiPool.length; i++) {
      var e = emojiPool[(start + i) % emojiPool.length]
      if (!used[e]) return e
    }
    return "💬"
  }
  function ago(ts) {
    if (!ts) return ""
    var s = Math.max(0, now / 1000 - ts)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    var d = new Date(ts * 1000)
    return Qt.formatDate(d, "MMM d")
  }
  function target(c) { return c.username ? c.username : String(c.id) }
  function cmd(o) { if (daemon.running) daemon.write(JSON.stringify(o) + "\n") }
  function showChat(c) { current = c; messages = []; sendError = ""; pending = ""; cmd({ cmd: "watch", id: c.id }); Qt.callLater(function() { composer.forceActiveFocus() }) }
  function back() { cmd({ cmd: "watch", id: null }); current = null; messages = []; sendError = ""; pending = ""; Qt.callLater(function() { keys.forceActiveFocus() }) }
  function openInApp(c) { Quickshell.execDetached([py, tgScript, "open", target(c)]); root.close() }
  function send(text) {
    var t = String(text).trim()
    if (!t || !current) return false
    sendError = ""
    pending = t
    cmd({ cmd: "send", id: current.id, text: t })
    return true
  }
  onOpenedChanged: { if (current) cmd({ cmd: "watch", id: opened ? current.id : null }) }
  function openApp() { Quickshell.execDetached([py, tgScript, "open", ""]); root.close() }
  function login() { Quickshell.execDetached(["omarchy-launch-tui", py, tgScript, "setup"]); root.close() }
  function refresh() { daemon.running = false; restart.interval = 300; restart.restart() }

  function apply(text) {
    try {
      var s = JSON.parse(text)
      if (s.kind === "history") {
        if (current && s.id === current.id) {
          messages = s.messages
          if (pending) for (var m = Math.max(0, s.messages.length - 3); m < s.messages.length; m++)
            if (s.messages[m].out && s.messages[m].text.trim() === pending.trim()) pending = ""
        }
        return
      }
      if (s.kind === "audio") {
        if (loadingKey === vkey(s.id, s.msg)) { playPath = s.path; playingKey = loadingKey; loadingKey = ""; player.running = false; playStart.restart() }
        return
      }
      if (s.kind === "typing") {
        var t = Object.assign({}, typingAt)
        if (s.on) t[s.id] = Date.now(); else delete t[s.id]
        typingAt = t
        tick = Date.now()
        return
      }
      if (s.kind === "error") {
        if (s.what === "audio") { loadingKey = ""; sendError = "Couldn't load that voice message (" + s.detail + ")." }
        if (s.what === "send") { sendError = "Message not sent (" + s.detail + "). Your text is back in the box."; if (pending && composer.text === "") composer.text = pending; pending = "" }
        return
      }
      if (s.kind === "sent") return
      updated = s.updated || 0
      if (s.ok) {
        problem = ""
        chats = s.chats || []
        folderName = s.folder || folderName
        if (!live && current && opened) cmd({ cmd: "watch", id: current.id })   // daemon (re)started: re-open the chat feed
        live = true
        if (current) for (var i = 0; i < chats.length; i++) if (chats[i].id === current.id) current = chats[i]
      } else {
        problem = s.error || "offline"
        otherFolders = s.folders || []
        live = false
      }
    } catch (e) {}
  }

  // ---------- processes ----------
  Process {   // last known state, so the panel is never empty while the daemon connects
    command: ["cat", root.cachePath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length && root.updated === 0) root.apply(text) }
  }
  Process {   // the live connection; starts with the shell, restarts itself if it drops
    id: daemon
    stdinEnabled: true
    command: [root.py, root.tgScript, "daemon"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.apply(line) } }
    onExited: {
      root.live = false
      if (root.problem !== "needs_login") { restart.interval = 15000; restart.restart() }
    }
  }
  Process {
    command: ["cat", Qt.resolvedUrl("emojis.json").toString().replace("file://", "")]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.emojiMap = JSON.parse(text) } catch (e) {} } }
  }
  Process {   // plays a downloaded voice message
    id: player
    command: ["mpv", "--no-video", "--really-quiet", "--no-terminal", root.playPath]
    onExited: root.playingKey = ""
  }
  Timer { interval: 60000; running: root.dictState === "listening"; onTriggered: root.stopDictation() }   // never record forever
  Timer { id: playStart; interval: 150; onTriggered: player.running = true }
  Process {
    id: pauser
    command: ["sh", Qt.resolvedUrl("media.sh").toString().replace("file://", ""), "pause"]
    onExited: {
      if (root.dictState !== "listening") return
      if (root.dictReleased) { root.dictState = ""; root.dictHint = "Hold the button while you speak."; resumer.running = true }
      else recorder.running = true
    }
  }
  Process { id: resumer; command: ["sh", Qt.resolvedUrl("media.sh").toString().replace("file://", ""), "resume"] }
  Process {   // microphone -> 16 kHz mono wav, only while the button is held
    id: recorder
    command: ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", root.recPath]
    onExited: {
      resumer.running = true
      if (root.dictState !== "listening") return
      if (!root.dictReleased) { root.dictState = ""; root.dictHint = "Couldn't use the microphone."; return }
      if (Date.now() - root.dictStart < 500) { root.dictState = ""; root.dictHint = "Hold the button while you speak."; return }
      root.dictState = "transcribing"
      stt.running = true
    }
  }
  Process {   // local speech-to-text (voxtype / Whisper on this PC); nothing leaves the machine
    id: stt
    command: ["sh", "-c", "f=\"$1\"; v=$(ffmpeg -hide_banner -nostats -i \"$f\" -af volumedetect -f null - 2>&1 | sed -n 's/.*mean_volume: \\(-\\?[0-9.]*\\) dB.*/\\1/p'); if [ -z \"$v\" ] || awk -v v=\"$v\" 'BEGIN{exit !(v < -52)}'; then echo __SILENT__; exit 0; fi; voxtype -q transcribe \"$f\" 2>/dev/null | grep -v -E '^(Loading audio file|Audio format|Processing )'", "sh", root.recPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.dictDone(text) }
    onExited: if (root.dictState === "transcribing") root.dictDone("")
  }
  Timer { id: restart; onTriggered: daemon.running = true }
  Process {
    command: ["sh", "-c", "for f in 'Atkinson Hyperlegible Next' 'Atkinson Hyperlegible' 'Lexend' 'OpenDyslexic' 'Noto Sans' 'Liberation Sans'; do fc-list \"$f\" family | grep -qi \"^$f\" && { echo \"$f\"; exit; }; done"]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim().length) root.readFamily = text.trim() }
  }
  Process {
    command: ["cat", root.prefsPath]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.length) root.loadPrefs(text) }
  }
  Timer { interval: 500; running: root.anyTyping || root.pending !== ""; repeat: true; onTriggered: { root.tick = Date.now(); root.phase = (root.phase + 1) % 3 } }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

  implicitWidth: toggleButton.implicitWidth
  implicitHeight: toggleButton.implicitHeight

  WidgetButton {
    id: toggleButton
    bar: root.bar
    text: "Telegram" + (root.unreadTotal > 0 ? " " + root.unreadTotal : "") + (root.problem !== "" ? " !" : "")
    fontSize: Style.font.caption
    tooltipText: root.problem === "needs_login" ? "Telegram: log in once to see your agents"
               : root.problem !== "" ? "Telegram: " + (root.problem === "no_folder" ? "no folder named Hermes found" : "offline, retrying")
               : root.chats.length ? root.unreadTotal + " unread across " + root.chats.length + " agents\nClick to open · right-click to refresh"
               : "Telegram"
    onPressed: function(button) {
      if (button === Qt.RightButton) root.refresh()
      else if (root.opened) root.close()
      else root.open()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: toggleButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(480 * root.zoom))
    contentHeight: panel.fittedContentHeight(Style.space(640), Style.space(760))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      blocked: composer.activeFocus
      onTextKey: function(text) { if (text === "r") root.refresh() }

      // ===== fixed top: title, comfort, summary, problems =====
      Column {
        id: controls
        visible: root.current === null
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.spacing.controlHeight * root.zoom
          T { ui: root; sz: Style.font.title; anchors.verticalCenter: parent.verticalCenter; text: "Telegram agents"; font.bold: true }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Chip { ui: root; sz: Style.font.caption; label: "Open app"; onClicked: root.openApp() }
            Chip { ui: root; sz: Style.font.caption; label: "Comfort"; active: root.comfortOpen; check: true; onClicked: { root.comfortOpen = !root.comfortOpen; root.savePrefs() } }
            Chip { ui: root; sz: Style.font.caption; label: "↻ Refresh"; onClicked: root.refresh() }
          }
        }

        Rectangle {
          visible: root.comfortOpen
          width: parent.width
          height: comfortFlow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          antialiasing: false
          color: root.solid(0.10)
          border.width: 1
          border.color: root.fade(0.5)
          Flow {
            id: comfortFlow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)
            Chip { ui: root; sz: Style.font.caption; label: "Text size " + Math.round(root.zoom * 100) + "%"; onClicked: { root.zoomPct = root.zoomSteps[(root.zoomSteps.indexOf(root.zoomPct) + 1) % root.zoomSteps.length]; root.savePrefs() } }
            Chip { ui: root; sz: Style.font.caption; label: "Send after dictating"; active: root.autoSend; check: true; onClicked: { root.autoSend = !root.autoSend; root.savePrefs() } }
            Chip { ui: root; sz: Style.font.caption; label: "Short previews"; active: root.simple; check: true; onClicked: { root.simple = !root.simple; root.savePrefs() } }
          }
        }

        T {
          visible: root.problem === "" && root.chats.length > 0
          width: parent.width
          ui: root
          font.bold: true
          wrapMode: Text.Wrap
          text: root.unreadTotal > 0
                ? root.unreadTotal + " unread from " + root.unreadChats + (root.unreadChats === 1 ? " agent" : " agents")
                : "All caught up · " + root.chats.length + " agents"
        }

        Rectangle {
          visible: root.problem !== ""
          width: parent.width
          height: problemCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          antialiasing: false
          color: root.solid(0.08)
          border.width: 2
          border.color: Commons.Color.urgent
          Column {
            id: problemCol
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(8)
            Row {
              spacing: Style.space(10)
              Mascot { px: Math.round(root.zoom * 2) * 10; anchors.verticalCenter: parent.verticalCenter }
              T {
                ui: root; font.bold: true; anchors.verticalCenter: parent.verticalCenter
                text: root.problem === "needs_login" ? "One-time login needed"
                    : root.problem === "no_folder" ? "No Telegram folder named “Hermes”"
                    : "Can't reach Telegram"
              }
            }
            T {
              ui: root; width: parent.width; wrapMode: Text.Wrap; opacity: 0.9
              text: root.problem === "needs_login" ? "Log in once so this widget can read your Hermes folder. It sends only what you type and press Send on, and marks a chat read only while you have it open here."
                  : root.problem === "no_folder" ? "Make a Telegram chat folder called Hermes and add your agents to it." + (root.otherFolders.length ? " Folders found: " + root.otherFolders.join(", ") + "." : "")
                  : "Retrying automatically. Showing the last known messages."
            }
            Chip { visible: root.problem === "needs_login"; ui: root; sz: Style.font.caption; label: "Log in to Telegram"; active: true; onClicked: root.login() }
            Chip { visible: root.problem !== "needs_login"; ui: root; sz: Style.font.caption; label: "↻ Try again"; onClicked: root.refresh() }
          }
        }

        T {
          visible: root.problem === "" && root.chats.length === 0
          width: parent.width
          ui: root
          wrapMode: Text.Wrap
          opacity: 0.85
          text: "Connecting to Telegram…"
        }
      }

      // ===== scrolling list of agent cards =====
      ListView {
        id: list
        visible: root.current === null
        anchors.top: controls.bottom
        anchors.topMargin: Style.space(8)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        spacing: Style.space(8)
        model: root.chats
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

        delegate: Rectangle {
          id: card
          required property var modelData
          readonly property bool unread: modelData.unread > 0
          width: list.width - Style.space(14)
          height: cardCol.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          antialiasing: false
          clip: true
          color: root.solid(cardMouse.containsMouse ? 0.20 : unread ? 0.14 : 0.08)
          border.width: unread ? 2 : Math.max(1, Style.normalBorderWidth)
          border.color: unread ? Commons.Color.accent : root.fade(cardMouse.containsMouse ? 0.9 : 0.55)

          MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.showChat(card.modelData)
          }

          Avatar {
            id: face
            size: Math.round(Style.space(40) * root.zoom)
            source: card.modelData.avatar
            emoji: root.emojiFor(card.modelData)
            fill: root.solid(0.16)
            edge: root.fade(0.5)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
          }

          Column {
            id: cardCol
            anchors.left: face.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            spacing: Style.space(4)

            Item {   // name left, badge + time right
              width: parent.width
              height: Math.max(nameText.implicitHeight, metaRow.implicitHeight)
              T {
                id: nameText
                ui: root
                font.bold: true
                text: card.modelData.name
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - metaRow.width - Style.space(10))
              }
              Row {
                id: metaRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Rectangle {
                  visible: card.unread
                  width: badge.implicitWidth + Style.space(10)
                  height: badge.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius
                  antialiasing: false
                  color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                  border.width: 2
                  border.color: Commons.Color.accent
                  T { id: badge; ui: root; sz: Style.font.caption; font.bold: true; anchors.centerIn: parent; text: card.modelData.unread + " new" }
                }
                T { ui: root; sz: Style.font.caption; opacity: 0.8; text: root.ago(card.modelData.date); anchors.verticalCenter: parent.verticalCenter }
              }
            }

            Rectangle { width: parent.width; height: 1; color: root.fade(0.3) }   // divider: name above, message below

            T {
              width: parent.width
              ui: root
              wrapMode: Text.Wrap
              maximumLineCount: root.simple ? 1 : 3
              elide: Text.ElideRight
              font.bold: card.unread
              opacity: 0.95
              text: root.isTyping(card.modelData) ? "✎ typing…" : (card.modelData.out ? "You: " : "") + (card.modelData.text || "No messages yet")
            }
            Chip {
              visible: !!card.modelData.voice
              ui: root; sz: Style.font.caption
              readonly property string k: root.vkey(card.modelData.id, card.modelData.mid)
              active: root.playingKey === k
              label: root.loadingKey === k ? "Loading…" : root.playingKey === k ? "■ Stop" : "▶ Play" + (card.modelData.dur ? " · " + Math.floor(card.modelData.dur / 60) + ":" + ("0" + card.modelData.dur % 60).slice(-2) : "")
              onClicked: root.togglePlay(card.modelData.id, card.modelData.mid)
            }
          }
        }
      }

      // ===== chat screen =====
      Item {
        id: chatView
        visible: root.current !== null
        anchors.fill: parent

        Item {   // header: back + who + open in Telegram
          id: chatHead
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.spacing.controlHeight * root.zoom
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Chip { ui: root; sz: Style.font.caption; label: "← Back"; onClicked: root.back() }
            Avatar {
              size: Math.round(Style.space(28) * root.zoom)
              source: root.current ? root.current.avatar : ""
              emoji: root.current ? root.emojiFor(root.current) : ""
              fill: root.solid(0.16)
              edge: root.fade(0.5)
            }
            T { ui: root; sz: Style.font.title; anchors.verticalCenter: parent.verticalCenter; font.bold: true; text: root.current ? root.current.name : "" }
          }
          Chip { ui: root; sz: Style.font.caption; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: "Open Telegram"; onClicked: root.openInApp(root.current) }
        }

        // composer: grows up to ~4 lines
        Rectangle {
          id: composerBox
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.min(Style.space(130) * root.zoom, Math.max(Style.spacing.controlHeight * root.zoom, composer.contentHeight + Style.space(14)))
          radius: Style.cornerRadius
          antialiasing: false
          color: root.solid(0.05)
          border.width: composer.activeFocus ? 2 : 1
          border.color: composer.activeFocus ? Commons.Color.accent : root.fade(0.6)
          Flickable {
            anchors.left: parent.left
            anchors.right: sendChip.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(7)
            clip: true
            contentHeight: composer.contentHeight
            contentY: Math.max(0, composer.contentHeight - height)
            TextEdit {
              id: composer
              width: parent.width
              wrapMode: TextEdit.Wrap
              color: root.barForeground
              selectionColor: Commons.Color.accent
              selectedTextColor: Commons.Color.background
              font.family: root.readable ? root.readFamily : Style.font.family
              font.pixelSize: Style.font.body * root.zoom
              font.letterSpacing: root.readable ? 0.7 : 0
              font.wordSpacing: root.readable ? 3 : 0
              Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                  if (root.send(composer.text)) composer.text = ""
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.back(); event.accepted = true
                }
              }
              T { visible: composer.text === "" && !composer.preeditText; ui: root; opacity: 0.6; text: "Message " + (root.current ? root.current.name : "") + "…  (Enter sends, Shift+Enter = new line)"; width: parent.width; elide: Text.ElideRight }
            }
          }
          Chip {
            id: sendChip
            ui: root
            sz: Style.font.caption
            anchors.right: parent.right
            anchors.rightMargin: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            label: "Send"
            active: composer.text.trim().length > 0
            onClicked: { if (root.send(composer.text)) composer.text = ""; composer.forceActiveFocus() }
          }
        }

        Column {   // status lines above the composer: dictation, typing, errors (each takes no space when hidden)
          id: status
          anchors.bottom: composerBox.top
          anchors.bottomMargin: Style.space(6)
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(6)

          Rectangle {   // "<name> is typing" with three stepping squares (steps, no flashing)
            id: typingBar
            visible: root.isTyping(root.current)
            width: typingRow.implicitWidth + Style.space(20)
            height: typingRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius; antialiasing: false
            color: root.solid(0.10); border.width: 1; border.color: root.fade(0.5)
            Row {
              id: typingRow
              anchors.centerIn: parent
              spacing: Style.space(8)
              T { ui: root; sz: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter; text: (root.current ? root.current.name : "") + " is typing" }
              Row {
                spacing: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                  model: 3
                  Rectangle { width: Style.space(7); height: width; antialiasing: false; color: root.barForeground; opacity: root.phase === index ? 1 : 0.25 }
                }
              }
            }
          }

          T {
            id: errLine
            visible: root.sendError !== ""
            width: parent.width
            ui: root; sz: Style.font.caption; font.bold: true; color: Commons.Color.urgent; wrapMode: Text.Wrap
            text: root.sendError
          }

          Item {   // hold-to-talk row
            id: dictRow
            width: parent.width
            height: Style.spacing.controlHeight * root.zoom
            Rectangle {
              id: talk
              readonly property bool on: root.dictState !== ""
              width: Math.round(Style.space(190) * root.zoom)
              height: parent.height
              radius: Style.cornerRadius
              antialiasing: false
              color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.30)
                   : talkMouse.pressed ? root.fade(Style.pressedFillAlpha)
                   : talkMouse.containsMouse ? root.fade(Style.hoverFillAlpha * 1.5) : root.fade(Style.normalFillAlpha)
              border.width: on ? 2 : Math.max(1, Style.normalBorderWidth)
              border.color: on ? Commons.Color.accent : root.fade(talkMouse.containsMouse ? 0.8 : Math.max(0.5, Style.normalBorderAlpha))
              T {
                ui: root; sz: Style.font.caption; anchors.centerIn: parent; font.bold: talk.on
                text: root.dictState === "listening" ? (root.dictLatched ? "● Listening… tap to finish" : "● Listening… let go to finish")
                    : root.dictState === "transcribing" ? "Turning speech into text…"
                    : "Hold to talk"
              }
              MouseArea {
                id: talkMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: root.dictPress()
                onReleased: root.dictRelease()
                onCanceled: if (!root.dictLatched) root.stopDictation()
              }
            }
            T {
              anchors.left: talk.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              ui: root; sz: Style.font.caption; opacity: 0.8; elide: Text.ElideRight
              text: root.dictHint !== "" ? root.dictHint : root.autoSend ? "Sends after you let go" : "Text lands in the box; check it, then Send"
            }
          }
        }

        ListView {
          id: msgList
          anchors.top: chatHead.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottom: status.top
          anchors.bottomMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          clip: true
          spacing: Style.space(8)
          model: root.shown
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
          onCountChanged: Qt.callLater(function() { msgList.positionViewAtEnd() })
          onHeightChanged: Qt.callLater(function() { msgList.positionViewAtEnd() })

          delegate: Item {
            id: msg
            required property var modelData
            readonly property real maxW: (msgList.width - Style.space(14)) * 0.82
            width: msgList.width - Style.space(14)
            height: bubble.height
            Rectangle {
              id: bubble
              anchors.right: msg.modelData.out ? parent.right : undefined
              anchors.left: msg.modelData.out ? undefined : parent.left
              width: Math.min(msg.maxW, Math.max(bodyText.visible ? bodyText.implicitWidth : 0, whenText.implicitWidth, voiceChip.visible ? voiceChip.implicitWidth : 0) + Style.space(20))
              height: bubbleCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              antialiasing: false
              opacity: msg.modelData.pending ? 0.6 : 1
              color: msg.modelData.out ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22) : root.solid(0.10)
              border.width: msg.modelData.out ? 2 : 1
              border.color: msg.modelData.out ? Commons.Color.accent : root.fade(0.5)
              Column {
                id: bubbleCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(3)
                Chip {
                  id: voiceChip
                  visible: !!modelData.voice
                  ui: root; sz: Style.font.caption
                  readonly property string k: root.vkey(root.current ? root.current.id : 0, modelData.id)
                  active: root.playingKey === k
                  label: root.loadingKey === k ? "Loading…" : root.playingKey === k ? "■ Stop" : "▶ Play voice message" + (modelData.dur ? " · " + Math.floor(modelData.dur / 60) + ":" + ("0" + modelData.dur % 60).slice(-2) : "")
                  onClicked: root.togglePlay(root.current.id, modelData.id)
                }
                T {
                  id: bodyText
                  ui: root
                  width: Math.min(implicitWidth, msg.maxW - Style.space(20))
                  wrapMode: Text.Wrap
                  visible: !modelData.voice
                  text: modelData.text || "[message]"
                  anchors.left: parent.left
                }
                T {
                  id: whenText
                  ui: root; sz: Style.font.caption; opacity: 0.75
                  text: modelData.pending ? "Sending…" : (modelData.out ? "You · " : "") + Qt.formatDateTime(new Date(modelData.date * 1000), (now / 1000 - modelData.date) > 72000 ? "MMM d, h:mm AP" : "h:mm AP")
                }
              }
            }
          }
        }
      }

      // ===== fixed footer =====
      T {
        id: footer
        visible: root.current === null
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        ui: root
        sz: Style.font.caption
        opacity: 0.8
        elide: Text.ElideRight
        text: (root.live ? "Live" : "Not live") + " · " + root.folderName + " folder · " + root.chats.length + " agents"
              + (root.updated ? " · updated " + root.ago(root.updated) : "")
      }
    }
  }
}
