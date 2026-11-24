# milk.bar-fit — the "no overlap" rule for the top bar

**The rule:** the bar is three blocks (left · middle · right). There must always be a gap
(12px) between blocks. If something grows (a media strip opens, tray drawer opens, a long
headline), Bar Fit shrinks text widgets to their short form, the one that frees the most room
first, until every gap is back. When room comes back, they expand again on their own.

**Collapse arrows (2026-11-13):** News and Claude/Codex usage each have their own arrow.
◂ = collapse, ▸ = expand. Saved per widget in ~/.cache/milk.bar-fit/<widget>.json.
News → 📰 · Claude/Codex usage → "Codex 100% · Claude 26%" (tighter of 5h/7d).
Other widgets are left alone on purpose. The old « button is hidden (this widget takes no room);
it only runs the overlap check. `milk-bar-collapse [on|off|toggle]` flips both.

**Calm rules (2026-11-13, after a "looks glitchy" report):** automatic shrinking never happens while
the pointer is on the bar (tray drawer/indicators open on hover); a change must hold for 1.5s;
an auto-shrunk widget only grows back when there's an extra 24px of room. Arrow clicks apply instantly.

## Making a widget follow the rule
Add to the widget root:
```qml
property bool fitCompact: false   // Bar Fit sets this; show the short form when true
property bool fitPinned: false    // the user's arrow choice (see milk.news for the pattern)
readonly property int fitPriority: 0   // optional: higher = tucked later (e.g. something the user just opened)
readonly property real fitFullWidth: 0 // optional: full width hint when it varies a lot
```
Third-party widgets get a sandboxed `bar`, so Bar Fit finds slots by walking its own window's
item tree (items with widgetKey/region/activeItem). Only horizontal bars; checks every 500ms.
Logs `milk.bar-fit: tucked [...]` to the shell journal when the tucked set changes.
Backups of the edited widgets: `Widget.qml.bak.20261112-235415-bar-fit` in each plugin.
