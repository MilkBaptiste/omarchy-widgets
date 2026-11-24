# Gigs (milk.gigs)

The main screen of **gig board**: a relaxed "jobs section of the newspaper" for contract work
(AI, integrations, apps, web, video, design, on-site tech help). Okanagan in person, remote across Canada.

This folder is the canonical copy (it is not in the git repo). Backend: `~/projects/gig-board`.
Style rules: `~/.claude/skills/milk-omarchy-widgets/SKILL.md`. Kit components (Chip/T/Mascot) come from
`~/.local/share/milk-omarchy-kit`; update them with `milk-widget sync gigs`.

## Paths

| What | Where |
| --- | --- |
| Widget | `~/.config/omarchy/plugins/milk.gigs/Widget.qml` |
| Board (read only) | `~/.cache/milk.gigs/board.json`, written by the backend every 6 h |
| Widget prefs | `~/.cache/milk.gigs/prefs.json` (categories, Comfort settings) |
| Backend command | `~/.local/bin/gigboard` |
| Backend logs | `~/.local/state/gig-board/gather.log` |

## How it works

- **Reading:** `cat board.json` when the panel opens, every 30 s while it is open, every 5 min while it is
  closed (keeps the bar count current), and a few quick re-reads after any button press. If the file can't be
  read or parsed, the last good copy stays on screen with a red "Couldn't read the latest board" line.
- **Commands** run detached (`Quickshell.execDetached`) so a long refresh survives a shell restart:
  - Refresh button / `r` key: `gigboard refresh` (gather now, no web sweep; the backend allows one per 10 min,
    otherwise it only re-exports).
  - Star / Save chip / `s` key: `gigboard mark save <id>` or `mark unsave <id>`.
  - Hide this gig chip: `gigboard mark hide <id>` (disappears right away; no undo in the widget).
  - Closing the panel: `gigboard mark seen` (only if something was NEW).
  - Links / hero card / `o` key: `xdg-open <url>`.
- **Keys:** Up/Down (or j/k) move, Enter/Space expands a row, `r` refresh, `s` star, `o` open the ad, Esc closes.

## What each state means

| You see | Meaning |
| --- | --- |
| Bar `Gigs 5` | 5 gigs arrived since you last closed the panel (`counts.new`). Just `Gigs` = nothing new. Fixed width. |
| `Refresh` | Idle. Click to check the boards now. |
| `Checking…` + bold line | A gather is running (`running` in board.json). Only trusted while the board is under 15 min old, so a crashed run can't leave it stuck. |
| `Fresh · 3 min ago` | You refreshed less than 10 min ago. Clicking again just re-reads; the backend won't hit the sites again yet. |
| **BEST NEW FIT** card | Highest-fit gig that is new this time. Click opens the ad. |
| `Nothing new since you last looked` | The board has gigs, none new. |
| `Nothing new worth your time right now. Checked 6:00 pm.` | The board is empty (everything was filtered out or nothing was posted). |
| `NEW` badge | First seen after your last visit. Badges stay put while the panel is open; they clear when you close it. |
| `8/10` (accent box, bold) | Fit score; 7+ is emphasised. |
| Footer `Castanet stale` | That source failed last time; its old listings are kept. `paused (blocked)` = it returned 403/429 and is backed off 24 h. `not checked yet` = never run (web search only runs on scheduled checks). |
| Red `This board is from …` | The board is over 8 h old; a scheduled check was probably missed. Press Refresh. |

Category chips are multi-select (check marks); **Any** clears them. "Other" gigs show only under Any.
Comfort (collapsed by default): Readable font, Text size 100/115/130 %, Simple view (title + fit only),
Show top 10/5/all, Row stripes + hover ruler.

## Maintenance

- After editing, run `/usr/lib/qt6/bin/qmllint Widget.qml` (unresolved `Style`/`qs.*` warnings are normal),
  then `milk-widget check gigs` and look at the screenshot.
- The board.json contract lives in `~/projects/gig-board` (see its README and `gigboard/export.py`).
- To test states without touching real data: back up `board.json`, copy a fixture over it, and point the
  `gigboard` property at a fake script so closing the panel doesn't run a real `mark seen`. Restore both after.
