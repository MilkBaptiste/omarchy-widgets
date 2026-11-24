# milk.project-tracker
Bar button "Projects", left of Telegram (shell.json right section; backup ~/.cache/shell.json.bak-before-project-tracker).

Data: snapshot of the Claude artifact "Project Tracker" (a Claude artifact) in
~/.cache/milk-project-tracker/projects.json (the id="tracker-data" JSON block, plus a "links" object).
Refresh: re-extract that block into the file, then Reload.

Local state (state.json, same dir): your status/stage/Now/Next edits (win until the snapshot changes that field),
next-step ticks, notes, and the "Sending to Today" queue. These do NOT sync to the web page's database.

Features: runway hero, Coming up (3), status bar, multi-select status + group filters, expandable rows,
Start (opens `claude` in a terminal on that next step), Next step done, + Today, + Note, Edit, Undo my edits,
links, Comfort (readable font, text size, Simple view). Not built: the web page's "App" button (needs a
milktracker:// handler) and the Tue/Thu auto-refresh.
Field.qml = text box; it counts focused boxes in root.typing so panel shortcut keys pause while typing.
