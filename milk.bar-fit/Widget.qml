import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar Fit: the "no overlap" rule for the top bar.
//
// Any bar widget that declares `property bool fitCompact` can be collapsed to a
// short icon form. Every half second this widget measures the bar sections on
// its own screen and predicts their edges with every widget at full size. If two
// sections would touch, it collapses the widget that frees the most room in one
// of the two touching sections, and repeats until there is a gap everywhere.
// Decisions come from measured full/compact widths, never from the current
// state, so it doesn't flicker back and forth. Widgets may also declare
// `fitPriority` (higher = tucked later).
//
// Each collapsible widget has its own arrow (fitPinned, saved per widget).
// This button collapses/expands both at once; `milk-bar-collapse` does the same.
BarWidget {
  id: root
  moduleName: "milk.bar-fit"

  property bool allPinned: false         // every collapsible widget is collapsed by the user
  property var pinItems: []
  property string pendingSig: ""
  property int pendingCount: 0
  property var tucked: []                // names collapsed automatically to stop an overlap
  property bool cantFit: false           // still overlapping with everything collapsed
  property var fullW: ({})               // moduleName -> last measured width when full
  property var compactW: ({})            // moduleName -> last measured width when compact
  readonly property real gapMin: Style.space(8)
  readonly property var names: ({ "milk.news": "News", "milk.ai-usage": "Claude/Codex usage" })

  // No button of its own any more (each widget has its own arrow): takes no room.
  implicitWidth: 0
  implicitHeight: 0

  function nameOf(key) { return names[key] || key.replace(/^[^.]*\./, "") }

  Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: root.fit()
  }

  // Third-party widgets get a sandboxed `bar`, so find this bar surface's
  // widget slots by walking up to the window and down its item tree.
  property var slotCache: []
  property int slotScan: 0
  function collectSlots(item, out, depth) {
    if (!item || depth > 60) return
    if (item !== root && ("widgetKey" in item) && ("region" in item) && ("activeItem" in item)) { out.push(item); return }
    var kids = item.children
    for (var i = 0; kids && i < kids.length; i++) collectSlots(kids[i], out, depth + 1)
  }
  function findSlots() {
    if (slotCache.length === 0 || ++slotScan % 6 === 0) {   // rescan every ~3s
      var top = root
      while (top.parent) top = top.parent
      var out = []
      collectSlots(top, out, 0)
      slotCache = out
    }
    return slotCache.filter(function(s) { try { return !!s && s.parent !== null } catch (e) { return false } })
  }

  function fit() {
    if (!bar || bar.vertical) return
    var slots = findSlots()
    var secs = { left: [], centerBegin: [], center: [], centerEnd: [], right: [] }
    var all = []
    var fw = fullW, cw = compactW
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.activeItem || !slot.visible || slot.width <= 0) continue
      if (!(slot.region in secs)) continue                       // tray drawer etc.
      var item = slot.activeItem
      var p = slot.mapToItem(null, 0, 0)
      var e = { key: slot.moduleName, item: item, x: p.x, w: slot.width,
                compactable: item !== root && ("fitCompact" in item), region: slot.region }
      if (e.compactable) {
        if (item.fitCompact) cw[e.key] = e.w; else fw[e.key] = e.w
        if ("fitFullWidth" in item && item.fitFullWidth > 0 && item.fitCompact) fw[e.key] = item.fitFullWidth
      }
      secs[slot.region].push(e)
      all.push(e)
    }
    fullW = fw; compactW = cw

    function widthIf(e, compact) {
      if (!e.compactable || compact === e.item.fitCompact) return e.w
      var known = compact ? cw[e.key] : fw[e.key]
      if (known !== undefined) return known
      return compact ? Math.min(e.w, Style.space(34)) : e.w   // unseen: guess, measured next pass
    }

    var plan = {}
    var items = [], every = true
    for (i = 0; i < all.length; i++) if (all[i].compactable) {
      var pin = !!all[i].item.fitPinned
      plan[all[i].key] = pin; items.push(all[i].item); if (!pin) every = false
    }
    pinItems = items
    allPinned = items.length > 0 && every

    // The bar has three blocks: left, the middle (centerBegin + center +
    // centerEnd, which touch by design) and right. Predict each block's edges
    // with the plan's widths and require a gap between neighbouring blocks.
    function block(regions) {
      var lo = 1e9, hi = -1e9, any = false
      for (var r = 0; r < regions.length; r++) {
        var list = secs[regions[r]], d = 0
        if (!list.length) continue
        var l = 1e9, h = -1e9
        for (var j = 0; j < list.length; j++) {
          l = Math.min(l, list[j].x); h = Math.max(h, list[j].x + list[j].w)
          if (list[j].compactable) d += widthIf(list[j], plan[list[j].key]) - list[j].w
        }
        var reg = regions[r]
        if (reg === "left" || reg === "centerEnd") h += d
        else if (reg === "right" || reg === "centerBegin") l -= d
        else { l -= d / 2; h += d / 2 }
        lo = Math.min(lo, l); hi = Math.max(hi, h); any = true
      }
      return any ? { regions: regions, lo: lo, hi: hi } : null
    }
    function firstClash(extra) {
      var seq = [block(["left"]), block(["centerBegin", "center", "centerEnd"]), block(["right"])].filter(function(b) { return b })
      for (var j = 0; j + 1 < seq.length; j++)
        if (seq[j].hi + gapMin + (extra || 0) > seq[j + 1].lo) return seq[j].regions.concat(seq[j + 1].regions)
      return null
    }

    var clash = firstClash(), stuck = false
    for (var guard = 0; clash && guard < 30; guard++) {
      var best = null, bestSave = 0, bestPrio = 0
      for (i = 0; i < all.length; i++) {
        var c = all[i]
        if (!c.compactable || plan[c.key] || clash.indexOf(c.region) < 0) continue
        // Lowest fitPriority goes first (a widget the user just opened says so),
        // then whichever frees the most room.
        var save = widthIf(c, false) - widthIf(c, true)
        var prio = ("fitPriority" in c.item) ? c.item.fitPriority : 0
        if (!best || prio < bestPrio || (prio === bestPrio && save > bestSave)) { best = c; bestSave = save; bestPrio = prio }
      }
      if (!best) { stuck = true; break }
      plan[best.key] = true
      clash = firstClash()
    }

    // Calm rules, so it never looks glitchy:
    // 1. Something already shrunk automatically only grows back if there is
    //    clearly room (an extra 24px), not the moment there is 1px.
    var wasAuto = {}
    for (i = 0; i < all.length; i++)
      if (all[i].compactable && all[i].item.fitCompact && !all[i].item.fitPinned) wasAuto[all[i].key] = true
    var growing = false
    for (var k in wasAuto) if (!plan[k]) growing = true
    if (growing && firstClash(Style.space(24))) for (k in wasAuto) plan[k] = true
    // 2. While the pointer is on the bar (tray drawer or indicators open, a
    //    widget being clicked) automatic changes wait until it leaves.
    //    Your own arrow clicks always apply straight away.
    var hovering = !!(bar && bar.centerSectionRevealHeld)
    // 3. A change must look the same for 1.5s (3 checks) before it happens.
    var sig = all.filter(function(e) { return e.compactable }).map(function(e) { return e.key + "=" + plan[e.key] }).join()
    if (sig !== pendingSig) { pendingSig = sig; pendingCount = 0 }
    pendingCount++
    var settled = pendingCount >= 3 && !hovering

    var auto = []
    for (i = 0; i < all.length; i++) {
      var a = all[i]
      if (!a.compactable) continue
      var want = plan[a.key]
      if (!settled) want = !!a.item.fitPinned || (a.item.fitCompact && !!wasAuto[a.key])
      if (a.item.fitCompact !== want) a.item.fitCompact = want
      if (want && !a.item.fitPinned) auto.push(nameOf(a.key))
    }
    if (auto.join() !== tucked.join()) { tucked = auto; console.log("milk.bar-fit: tucked [" + auto.join(", ") + "]" + (stuck ? " (still too full)" : "")) }
    cantFit = stuck
  }

  WidgetButton {
    id: button
    visible: false
    bar: root.bar
    fontSize: Style.font.caption
    active: root.allPinned
    text: root.allPinned ? "»" : root.tucked.length ? "« " + root.tucked.length : "«"
    tooltipText: (root.allPinned
        ? "News and Claude/Codex usage are collapsed.\nClick to expand."
        : "Click to collapse News and Claude/Codex usage."
          + (root.tucked.length ? "\n\nTucked to stop overlap: " + root.tucked.join(", ") : "\n\nNothing is overlapping."))
      + (root.cantFit ? "\n\nStill too full: move or remove a widget." : "")
    onPressed: function(b) { var v = !root.allPinned; root.pinItems.forEach(function(it) { if (typeof it.setFitPinned === "function") it.setFitPinned(v) }); root.fit() }
  }
}
