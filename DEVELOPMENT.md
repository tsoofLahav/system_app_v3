# Development guide (v3 in progress)

**This is the working memory for the coding agent.** When the user says “remember this”, add it here.

Not for the production agent — that agent reads its instructions from the database (`agent_configs.system_prompt`), not this file.

---

## Current state

We are building a **new version** of system_app on `main`. Much of the codebase is mid-rewrite and still needs work. Treat incomplete areas as expected, not finished.

### v1 reference (GitHub)

Behavior removed in the rewrite still exists on the legacy branch. Use it when porting or recovering something that was lost:

```bash
git fetch origin
git checkout legacy/v1
```

Remote: `origin/legacy/v1` on [github.com/tsoofLahav/system_app_v3](https://github.com/tsoofLahav/system_app_v3/tree/legacy/v1)

Back to current work: `git checkout main`

### Deploy / test loop

**After backend changes, push to `main`** so Render redeploys and the Flutter app can be tested against the live API. Frontend-only changes do not need a backend deploy.

---

## System areas

The code is physically split by area. Each area owns its folder and an `AREA.md` with its rules and logic. Matching areas exist on both sides where relevant, and their docs mirror each other.

| Area | Backend | Frontend |
|------|---------|----------|
| **File structure & functionality** | [`areas/files/AREA.md`](system_app_back_end/areas/files/AREA.md) | [`areas/files/AREA.md`](system_app_front_end/lib/areas/files/AREA.md) |
| **Production agent** | [`areas/production_agent/AREA.md`](system_app_back_end/areas/production_agent/AREA.md) | [`areas/production_agent/AREA.md`](system_app_front_end/lib/areas/production_agent/AREA.md) |
| **Automations** | [`areas/automations/AREA.md`](system_app_back_end/areas/automations/AREA.md) | [`areas/automations/AREA.md`](system_app_front_end/lib/areas/automations/AREA.md) |
| **Objects** (incl. **tasks**) | [`areas/objects/AREA.md`](system_app_back_end/areas/objects/AREA.md) | [`areas/objects/AREA.md`](system_app_front_end/lib/areas/objects/AREA.md) |
| **UI** — visual style only | — | [`areas/ui/AREA.md`](system_app_front_end/lib/areas/ui/AREA.md) |
| **UX** — flow and experience | — | [`areas/ux/AREA.md`](system_app_front_end/lib/areas/ux/AREA.md) |

Area maps: [backend](system_app_back_end/areas/README.md) · [frontend](system_app_front_end/lib/areas/README.md)

**Working rule:** if you change behavior in an area, update that area's `AREA.md` in the same commit. If the change spans front and back, update both.

### Where the production agent's own file lives

| Layer | Location |
|-------|----------|
| Git source (edit here) | [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) |
| Runtime | `agent_configs.system_prompt` in PostgreSQL |
| Sync (local) | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |
| Sync (Render) | Automatic on web boot (`RENDER=true`) via internal DB URL |

---

## Remembered notes

_(Dated bullets — added when the user asks to remember something.)_

- **2026-07-14** — Push to `main` after backend changes to test on Render.
- **2026-07-14** — v3 rewrite in progress; use the `legacy/v1` branch on GitHub when old behavior is needed as reference.
- **2026-07-14** — Production agent prompt lives in `content/production_agent/system_prompt.md`, not in backend dev docs; it is synced into `agent_configs.system_prompt`.
- **2026-07-27** — Code is organized by area (`areas/<area>/`) in both projects, each with its own `AREA.md`. UI and UX are frontend-only and strictly separated: UI is look, UX is flow.
- **2026-07-27** — Known unresolved issues live in [`BACKLOG.md`](BACKLOG.md), grouped by area. We clear one area at a time; the current focus is **objects in files** (file integration first, then deeper object behaviour).
- **2026-07-27** — A file must read as one continuous text. Paragraphs, bullets, and table cells are *segments* of a single caret/selection owned by `DocumentTextFlow`; anything new that holds editable text has to register a segment.
- **2026-07-27** — **There is only one marking.** Every action (right-click, clipboard, formatting, and AI) resolves its target through `DocumentMark`: the marking if there is one — across as many parts as it covers — otherwise the line at the caret. Never read a single field's selection to decide what an action affects.
- **2026-07-27** — **A bullet in a list and a row in a table each count as one line of text.** Settle any caret or marking question by asking what a plain line would do: arrow up lands on the *last* line of what is above, marking a whole row and deleting removes the row, marking every row removes the table. Rules in the files [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md).
- **2026-07-27** — An arrow key moves the caret the direction it points **on screen**, in Hebrew as in English. This is done by overriding the text field's motion *intents* (`rtl_caret_motion.dart`), not by handling key events — never reimplement caret movement in a key handler, it breaks key repeat and rebuilds the file on every keypress. Text direction currently follows the UI language, not the text.
- **2026-07-27** — A list has one style; points vs numbers is switched on the existing list from its right-click menu, never offered as two things to insert.
- **2026-07-27** — **The layout decides which files are on screen.** A topic stores `file_layout`, a file stores `order_index`, and that is all: the layout's slots reach a certain way down the order and everything past them is off screen, reachable only by arranging. There is no flag on a file saying it matters — that would be a second source of truth for the same question. Rules in the UX [`AREA.md`](system_app_front_end/lib/areas/ux/AREA.md); `files.is_essence` was dropped in migration `004`.
- **2026-07-27** — A new file is added **first** in its topic, so it is always visible.
- **2026-07-27** — The topic colour wash is painted **full-window** by `AppShellCanvas`, behind the glass sidebar and the bottom bar. Chrome always floats above the room.
- **2026-07-31** — Agent interaction plan wrapped (after objects): [`working on the agent interaction.md`](working%20on%20the%20agent%20interaction.md). Responses API + per-flow conversation; scope + hints (file/date/…); tools `patch_file` / `move_text` / `rewrite_file`; pending reviews in DB; archive files read-only.
- **2026-07-27** — Glass dialogs share one language: `AppAdaptiveDialogShell`, labels **above** fields (`AppDialogField`), multi-choice chips with the chosen one in bright teal (`AppDialogChoiceField`), and pickers that open a **secondary** dialog (`AppDialogPickerField`). Preferences is the reference. The file `⋯` opens the same `AppContextMenu` as a right-click.
- **2026-07-27** — **A registry must never notify its listeners from `dispose`.** Flutter locks the tree while unmounting, so a listener rebuilding then throws *setState() called when widget tree was locked* — once per listener, which buries the console. Registries bump through [`FrameSafeNotifier`](system_app_front_end/lib/shared/utils/frame_safe_notifier.dart), which notifies immediately when the tree is free and waits for the end of the frame when it is not. Waiting always is not an option: post-frame callbacks do not schedule a frame, so a bump made while idle would never arrive.
- **2026-07-27** — **Files wear their topic's colour**, at a strength fixed per file id (`AppColors.fileTintStrength`) so a pane keeps its shade through reordering, restarts, and other devices. Never derive the shade from position or content. The full cross-app style spec is the UI [`AREA.md`](system_app_front_end/lib/areas/ui/AREA.md) — colours, type, spacing, glass, controls, dialogs — and no `Color(0x…)` or font size belongs outside `areas/ui/`.
- **2026-07-31** — **Files vs objects split:** in-file embed widgets live under [`files/editor/embeds/`](system_app_front_end/lib/areas/files/editor/embeds/) (presentation, flow, menus, Move Mode). Objects owns data + special qualities — **tasks/views**, **info links**, payloads (e.g. `tasks.status`). Thin overlay: embeds call object services/controls; they do not own those fields. See both [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md) files.
- **2026-07-27** — **Objects in a file** are top-level embed blocks. The document owns position; the object owns data. Double-click enters Move Mode. Enter on an empty final task / info line / graph column exits below without destroying the object.
- **2026-07-27** — **Never rebuild the document editor (or the Shortcuts tree) from `AppState.notifyListeners` mid-keystroke.** That desyncs Flutter's `HardwareKeyboard` and loops `KeyDownEvent … physical key is already pressed` (same class of bug as 2026-07-15). Silent document/object saves (`notify: false`), debounce embed field saves, and only schedule embed rebuilds post-frame. Hot reload can leave keys stuck — use a **full restart** to clear it.
- **2026-08-03** — Object graph / tags / diagram need migration **`006_object_graph.sql`** applied manually on the Render Postgres DB before (or right after) deploying the backend that uses `tags.icon`, `links.kind`, and `links.anchor`.
- **2026-08-07** — Agent/automation **run defaults** (`apply_mode`, etc.) live in [`shared/run_config.py`](system_app_back_end/shared/run_config.py). Call sites import them; do not re-hardcode fallbacks in routes, runner, or FE services. Manual consult omits `apply_mode` so the backend default wins. FE UI for automation create may keep a twin constant in `agent_run_defaults.dart` that must match.
- **2026-08-07** — Production-agent **writing/editing guidance** must be written as short, structured **instructions** (numbered steps, MUST / MUST NOT), not tip-style prose. The model already gets a lot of context; soft advice gets ignored. Scenario-specific jobs (e.g. “notes → update plan”) belong in topic/automation prompts, not in generic tool descriptions.

---

## Related

| Doc | Purpose |
|-----|---------|
| [`BACKLOG.md`](BACKLOG.md) | Known unresolved issues, grouped by area |
| [`CONSTITUTION.md`](CONSTITUTION.md) | Product principles — read-only for agents |
| [`AGENTS.md`](AGENTS.md) | Monorepo entry and task routing |
| [`system_app_back_end/docs/API.md`](system_app_back_end/docs/API.md) | REST endpoint reference |
| [`content/README.md`](content/README.md) | DB-bound app content |
