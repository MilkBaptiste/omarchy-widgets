# Telegram (v2, rebuilt 2026-11-08 by Claude)

One card per agent chat in the Telegram folder named **Hermes**: name, unread badge, latest message, time.
Profile photos are cached in ~/.cache/milk-telegram/avatars (emoji from emojis.json is the fallback when a bot has no photo). "typing…" shows on the card and in the chat; a sent message shows dimmed "Sending…" until Telegram confirms.
Click a card -> in-widget chat screen: last 40 messages, type and send (Enter sends, Shift+Enter = new line), "Open Telegram" button for the app. Opening a chat marks it read; closing the panel or going Back stops that. **Refresh** (or right-click the bar button, or R) re-reads everything.
Bar button shows the total unread count (`Telegram 3`), `!` when login/folder/network needs attention.

**Live + autostart:** the widget starts `tg.py daemon` when the shell starts. It keeps a read-only Telegram
connection and pushes a new snapshot on every message/read/edit; it also re-checks every 2 min and restarts itself
15 s after a drop. Last state is cached at `~/.cache/milk-telegram/state.json` so the panel is never empty.

**One-time login:** click "Log in to Telegram" in the panel (or `~/.local/share/milk-telegram/venv/bin/python tg.py setup`).
Needs api_id/api_hash from https://my.telegram.org (API development tools), then phone + code (+ 2FA).
Stored 0600: `~/.config/omarchy/credentials/telegram-api.json`, session `~/.local/share/milk-telegram/session.session`.
The widget sends only what you type and send in its chat screen, and marks a chat read only while it is open there. It never edits or deletes. Anyone with the session file can act as you: keep it private.

Folder name: env `MILK_TELEGRAM_FOLDER` (default Hermes). Folders with "bots" / groups flags and manual chats are all handled.
Backend: Telethon in `~/.local/share/milk-telegram/venv`. Prefs (Comfort): `~/.cache/milk-telegram/prefs.json`.
Old Codex version backed up outside the plugins folder (scratchpad); it only watched the tray icon.
Maintenance: `milk-widget sync telegram`, `milk-widget check telegram`.

## Voice (added 2026-11-08)
- **Play:** voice messages get a "▶ Play" button (on the agent card when the latest message is voice, and in the chat).
  Downloaded once to ~/.cache/milk-telegram/audio and played with mpv. Click again to stop.
- **Dictate:** "Hold to talk" in the chat screen. Tap-and-hold (or hold the button) records; let go to finish. A single quick tap
  latches listening on and a second tap stops it (easier on a touchpad). Music/video playing over MPRIS is paused while recording
  and resumed after (media.sh). Speech-to-text is 100% local: voxtype transcribe (Whisper, model from ~/.config/voxtype). The text lands in the
  message box; Comfort > "Send after dictating" sends it straight away. Max 60 s per recording. Silent clips are skipped.
- **Mic level caveat:** this laptop's internal mic has Capture 100% + Internal Mic Boost 100% (+60 dB) which clips everything. About
  Capture 40 / Boost 1 gives a clean level: `amixer -c 0 sset Capture 40; amixer -c 0 sset 'Internal Mic Boost' 1`.
- Speed: base.en on this CPU (no GPU) takes roughly 2-3x the clip length. `tiny.en` would be faster but less accurate.
