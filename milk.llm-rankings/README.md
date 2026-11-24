# LLM Rankings (v5.2)

**Every filter is combinable.** Reasoning and Lab chips are multi-select (click to toggle, a check mark shows what is on;
Any/All clears the group). Example: Fastest + Low reasoning + OpenAI and Anthropic together, on the chart. Min IQ, Pinned,
the category and Show top N combine with them. Older saved single-value prefs are migrated automatically.
The chart adds a lab legend and, when 2+ labs are selected, a "#1" marker for the best model of EACH lab.

**Compare mode** (title row: List | Chart | Compare): pick any two categories, A and B (e.g. Smartest vs Cheapest).
Shows a plain-English verdict first, both winners as cards, a head-to-head table (check mark = better side) and each
side's top 5. Click any model to jump to it in the list. Reasoning, Lab, Min IQ and Pinned filters apply to both sides.

**Chart now follows everything**: it plots exactly the rows the list shows, so Reasoning, Lab, Min IQ, Pinned, the
category tab and "Show top N" all apply. The category winner is ringed and labelled "#1". Header shows what is plotted.

**Models tracked:** every model that has an Intelligence Index score, PLUS every model (scored or not) from the
labs in `labs.json` (default: OpenAI, Anthropic, Google, Meta, SpaceXAI, Alibaba; edit the file to change them,
names must match Artificial Analysis exactly, a missing lab is flagged in the panel). Unscored models still have
price and speed, so they appear in Cheapest/Fastest when **Min IQ: any**. Other labs' scored models sit under **Other labs**.

**Refresh:** automatically every hour (and at shell start), and the **Refresh** button anytime.
One full refresh = 4 API pages (200 models/page). Free tier = 100 requests/day, so automatic refreshes stop at 90
and the button works up to 98; auto skips if data is under 50 min old, the button if under 60 s old.
Anything else using the same API key shares the quota.

**Look:** square, theme-token buttons from the shared milk kit (`Chip.qml`, `T.qml`, `Mascot.qml`, synced from
`~/.local/share/milk-omarchy-kit` with `milk-widget sync llm-rankings`). Skill: `~/.claude/skills/milk-omarchy-widgets`.

Everything is a button; no hotkeys needed (arrows/Enter/R still work).

- **8-bit mascots** (`mascots/*.png`, original 10x10 sprites, regenerate with `python3 -I make_mascots.py`)
  beside every lab: rows, lab chips, answer card, chart dots use the lab colour. Unknown labs get a robot.
- **Answer card** at the top: the #1 model for the current category, big, with its key number.
- **Sortable headers**: click IQ / In $ / Out $ / tok/s / 1st tok / IQ per $; click again to reverse.
- **Pins**: tap the star on any row; "Pinned" chip shows only pinned models.
- **Chart**: List | Chart toggle. IQ vs blended price (log). Orange line = best IQ at each price.
  Hover for details, click a dot to jump to that model.
- **Comfort** (ADHD / dyslexia): Readable font (first installed of Atkinson Hyperlegible, Lexend,
  OpenDyslexic, else Noto Sans; wider letter/word/line spacing), Text size 100/115/130%,
  Simple view (IQ + one key column), Show top 5/10/all, Row stripes + hover ruler.
  Active toggles show a check mark so state is never colour-only. Settings persist in prefs.json.

Click **LLMs** in the bar. Everything is a button; no hotkeys needed.

- **Categories:** Smartest (Intelligence Index), Cheapest (blended $/1M tokens, 3 input : 1 output),
  Best value (IQ points per blended $), Fastest (tok/s), Quickest start (time to first token).
- **Reasoning lock:** Any / Off / Low / Med / High / XHigh / Max (only levels present in the data).
  Picks that level for every model family at once. Models with no reasoning modes always stay visible.
- **Lab chips:** filter to the six strongest labs. **Min IQ** cycles any/30/40/50 (default 30, which
  hides free but near-useless models that would otherwise top Cheapest and Best value).
- Click a row for exact prices, speed, latency, Open on Artificial Analysis, Copy name.
- Choices persist in `~/.cache/milk-llm-rankings/prefs.json`. Arrow keys, Enter and R still work.
- All scored models (about 100) are cached; the reasoning level is parsed from the model name
  (`Claude Opus 5.5 (Max, Default Fallback)` -> Claude Opus 5.5 + Max badge).

## One-time setup

Create an account and free API key at https://artificialanalysis.ai/login.
Click **API key setup** in the widget and paste the key into the terminal's
hidden prompt. Or run:

```bash
python3 -I ~/.config/omarchy/plugins/milk.llm-rankings/setup-key.py
```

Press **R** in the widget after saving the key. It is stored in
`~/.config/omarchy/credentials/artificial-analysis.key` with permissions 0600.
The fetcher also supports the environment variable `ARTIFICIAL_ANALYSIS_API_KEY`.
Never put keys in QML, screenshots, source files or chat.

## Refresh and cache

Fetches all API pages before sorting to obtain the actual top 25. Uses stable
model IDs for deduplication. Refreshes at startup and every hour (see v5 notes above). Right-click
the button or press R for a manual refresh. Successful fetches are reused for
five minutes across reloads and monitors. A file lock serializes refreshes and
an on-disk UTC counter caps this widget at 90 automatic requests/day (98 with the button), below the published
free tier allowance of 100 requests/day. Other apps using the key share the
provider's quota. No paid endpoints are called.

Cache: `~/.cache/milk-llm-rankings/artificial-analysis.json`. Errors preserve
saved rankings and their original timestamp. `LLMs *` indicates stale data.
The old Arena cache is separate and never shown as Artificial Analysis data.
Context windows and licensing are excluded from the free endpoint, so the panel
shows speed and latency instead. Free data is for internal use with attribution.

## Validation and history

2026-11-04: v3 rebuilt by Claude (categories, reasoning lock, filters). Earlier: created as an Arena/OpenRouter widget, then switched to Artificial
Analysis at the user's request. Previous plugin files are backed up under
`~/.local/state/milk-llm-rankings/backups/20261104-153433/`.
The initial shell layout backup remains next to `shell.json`.

The agent environment cannot resolve external API hosts or reach desktop IPC.
Live authentication remains pending entry of the user's free API key. No sample
rankings are installed into the real cache.
