# AI usage header

Installed 2026-10-19 by Codex. Two compact rounded capsules explicitly display percentages as **% used**, with stacked five-hour (`5h`) and weekly (`7d`) progress bars. Codex uses muted teal and Claude uses warm clay; amber starts at 70% and red at 90%. Hover for timestamps, reset dates and errors. A hollow amber dot and faded meters mean stale/unavailable. Expired windows display a dash until fetched again.

The bar runs `usage.py` every 15 seconds to pick up the shared cache; successful service requests are spaced two minutes apart. Errors back off up to 15 minutes. Multiple monitors share a locked cache in `~/.cache/ai-usage/`.

Codex uses the official `account/rateLimits/read` app-server RPC with your existing CLI login. Claude reads the existing Claude Code OAuth credentials and calls `https://api.anthropic.com/api/oauth/usage`; this internal endpoint may change. Credentials are neither copied nor logged. If login expires, sign into the relevant CLI again. The widget does not refresh or replace Claude credentials.

The plugin is enabled as `milk.ai-usage` in `~/.config/omarchy/shell.json`. A timestamped backup of the original layout sits beside that file. Omarchy hot-reloads plugin/config changes. If the widget has not appeared, run `omarchy-shell shell rescanPlugins` in your desktop terminal.

Validation: Python compilation, QML lint with a minimal host stub, fixture tests for parsing/cache failures. Live endpoint access and desktop IPC were unavailable inside the Codex sandbox, so live data and actual rendering still need confirmation on the desktop.

Sources:
- https://learn.chatgpt.com/docs/app-server
- https://code.claude.com/docs/en/statusline

Visual update, 2026-10-19: 332 × 26 px footprint, aligned figures, subtle hover borders, animated meters and usage detail tooltips. Validated with QML lint and an actual offscreen Qt render using normal, warning, stale and unavailable fixtures. Desktop rendering remains unverified from this sandbox.

Hover repair, 2026-10-19: Replaced the shared header tooltip with a widget-owned multiline PopupWindow, explicit dimensions, dark background and light text. Both header percentages now explicitly say "% used"; meter fills continue to use consumed utilization directly. Saved a timestamped Widget.qml backup. Offscreen Quickshell loaded both fixture popups with full multiline content (330 × 143 px without reset rows); live desktop hover remains unverified because session IPC is inaccessible.

Follow-up, 2026-10-19: User still sees white hover bar. Live shell log records reload notifications but no revision-1.2 component completion. Changing the entry point to a new UsageWidget.qml produced a live "File name case mismatch" error; restored Widget.qml entry point. Suspect stale QML engine/directory cache. A full `omarchy restart shell` from the desktop terminal is needed; sandbox cannot reach desktop IPC. Prior offscreen loading did not prove the desktop applied changes.
