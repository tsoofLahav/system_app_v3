# Notes (situational reference)

Not for every task — read the section that matches what you are touching. [`DEVELOPMENT.md`](DEVELOPMENT.md) is the always-read guide.

When the user says “remember this”, add the note here under the matching section, with a date.

---

## Editor keyboard safety

**Read before changing** `SuperDocumentEditor`, embeds, `AppState` notify paths, or any in-document `TextField`.

Flutter desyncs when a `TextField` / `FocusNode` is disposed or the editor tree remounts **while a physical key is still down**. Symptom: looping console errors

`KeyDownEvent is dispatched, but the state shows that the physical key is already pressed`

This class of bug comes back often after embed/save/focus changes. (Reconfirmed **2026-08-11** after table payload patches remounted Super Editor while typing.)

### MUST NOT

1. Wrap `DocumentEditor` / `SuperDocumentEditor` in `ListenableBuilder(listenable: appState)` (or any parent that rebuilds the whole file on every `notifyListeners`).
2. Call `notifyListeners()` / `loadEmbedsForFile(notify: true)` / `_reloadEmbedsForOpenFiles` **from a keystroke path** (cell/title/body `onChanged`, every character).
3. `setState` the Super Editor (or replace `Editor` / remount embeds) while `HardwareKeyboard.instance.physicalKeysPressed` is non-empty — unless the change is purely visual and keeps the same `FocusNode`s.
4. Dispose or recreate cell/task/info `FocusNode`s / controllers in `didUpdateWidget` while those fields have focus or keys are down.
5. Overwrite live controller text from a stale embed cache while the user is typing in that embed.
6. **Notify listeners from a registry's `dispose`.** Flutter locks the tree while unmounting, so a listener rebuilding then throws *setState() called when widget tree was locked* — once per listener, which buries the console.

### MUST

1. **Silent saves:** document + object payload/title patches use `notify: false` (or patch cache in place with no notify).
2. **Debounce** embed field PATCHes (info / table / tasks already do ~400ms) — never hit the network on every character without a timer.
3. **Patch cache before await** on embed writes so a remount cannot re-seed empty content mid-flight.
4. On `AppState` embed-list changes, rebuild Super Editor only for **structural** changes (id / type / order). Payload-only list replacements must not `setState` the editor. If a structural rebuild is required and keys are down, use `runAfterKeystroke` ([`editor_key_handoff.dart`](system_app_front_end/lib/areas/files/editor/editor_key_handoff.dart)).
5. **Tab / Escape** focus handoff → `runNextFrame`. **Destructive** deletes (empty Backspace removing a row/object) → `runAfterKeystroke`.
6. Keep stable embed identities (`embed:<objectId>`, `GlobalKey` where State must survive parent rebuilds).
7. Registries bump through [`FrameSafeNotifier`](system_app_front_end/lib/shared/utils/frame_safe_notifier.dart), which notifies immediately when the tree is free and waits for the end of the frame when it is not. Waiting always is not an option: post-frame callbacks do not schedule a frame, so a bump made while idle would never arrive.

### After you change editor code — smoke-check

- Type quickly in: paragraph, info body, task title, table cell, chart-table cell.
- Tab into an object, type, Escape out, type in the paragraph below.
- If the assertion appears: **full restart** the app (hot reload can leave keys stuck); then fix the remount/notify path — do not ignore it.

Detail and fluent-text rules: files [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md) · [`FLUENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/FLUENT_TEXT.md).

---

## Files and text

- **2026-08-09** — **Marker-text SoT (v4):** files store `%%system_app_document v4` pointer-marker text ([`DOCUMENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/DOCUMENT_TEXT.md)); agent text expands/collapses objects. Legacy v3 JSON migrates on read (spans dropped until span encoding).
- **2026-08-09** — **Super Editor file surface:** runtime editing = [`SuperDocumentEditor`](system_app_front_end/lib/areas/files/editor/super_document_editor.dart) + [`marker_super_editor_bridge`](system_app_front_end/lib/areas/files/model/marker_super_editor_bridge.dart). Pin `super_editor: 0.3.0-dev.50` (dev.51+ needs Flutter `TextInputStyle`).
- **2026-07-27** — A file must read as one continuous text. The file body is edited with **Super Editor**; embed-internal fields may still use local text fields. See files [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md).
- **2026-07-27** — **There is only one marking.** Every action (right-click, clipboard, formatting, and AI) resolves its target through `DocumentMark`: the marking if there is one — across as many parts as it covers — otherwise the line at the caret. Never read a single field's selection to decide what an action affects.
- **2026-07-27** — **A bullet in a list and a row in a table each count as one line of text.** Settle any caret or marking question by asking what a plain line would do: arrow up lands on the *last* line of what is above, marking a whole row and deleting removes the row, marking every row removes the table. Rules in the files [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md).
- **2026-07-27** — A list has one style; points vs numbers is switched on the existing list from its right-click menu, never offered as two things to insert.
- **2026-08-09** — Fluent text with embeds: [`FLUENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/FLUENT_TEXT.md) — no empty neighbors after move/delete, edge landing, stable embed remount.
- **2026-08-07** — **RTL solution** for the file editor is gathered under [`system_app_front_end/lib/areas/files/rich_text/rtl/`](system_app_front_end/lib/areas/files/rich_text/rtl/RTL.md) (`RTL.md` + `rtl.dart`). Do not invent caret/direction policy outside that folder.

---

## Objects and embeds

- **2026-07-31** — **Files vs objects split:** in-file embed widgets live under [`files/editor/embeds/`](system_app_front_end/lib/areas/files/editor/embeds/) (presentation, flow, menus, Move Mode). Objects owns data + special qualities — **tasks/views**, **info links**, payloads (e.g. `tasks.status`). Thin overlay: embeds call object services/controls; they do not own those fields. See both [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md) files.
- **2026-07-27** — **Objects in a file** are top-level embed blocks. The document owns position; the object owns data. Double-click enters Move Mode. Enter on an empty final task / info line / graph column exits below without destroying the object.
- **2026-08-10** — **Atomic object blocks:** SE caret treats embeds as one block. **Tab**/click opens; **Escape** returns to the block; **Enter** inserts a line below. Tab/Escape use `runNextFrame`; destructive deletes still use `runAfterKeystroke`. Info is one text field (first line = title). No arrow auto-enter/exit. Rules: [`FLUENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/FLUENT_TEXT.md).
- **2026-08-11** — **Tables + charts:** one object type `table` (`payload.rows` + optional `payload.chart`). `[GRAPH id]` is sugar for chart-on tables. Shared UI: [`table_embed.dart`](system_app_front_end/lib/areas/files/editor/embeds/table_embed.dart) + [`RichTableEditor`](system_app_front_end/lib/areas/files/rich_text/rich_table_editor.dart).

---

## Layout and visibility

- **2026-07-27** — **The layout decides which files are on screen.** A topic stores `file_layout`, a file stores `order_index`, and that is all: the layout's slots reach a certain way down the order and everything past them is off screen, reachable only by arranging. There is no flag on a file saying it matters — that would be a second source of truth for the same question. Rules in the UX [`AREA.md`](system_app_front_end/lib/areas/ux/AREA.md).
- **2026-07-27** — A new file is added **first** in its topic, so it is always visible.
- **2026-07-27** — The topic colour wash is painted **full-window** by `AppShellCanvas`, behind the glass sidebar and the bottom bar. Chrome always floats above the room.
- **2026-07-27** — **Files wear their topic's colour**, at a strength fixed per file id (`AppColors.fileTintStrength`) so a pane keeps its shade through reordering, restarts, and other devices. Never derive the shade from position or content. The full cross-app style spec is the UI [`AREA.md`](system_app_front_end/lib/areas/ui/AREA.md) — colours, type, spacing, glass, controls, dialogs — and no `Color(0x…)` or font size belongs outside `areas/ui/`.

---

## Dialogs and UI language

- **2026-07-27** — Glass dialogs share one language: `AppAdaptiveDialogShell`, labels **above** fields (`AppDialogField`), multi-choice chips with the chosen one in bright teal (`AppDialogChoiceField`), and pickers that open a **secondary** dialog (`AppDialogPickerField`). Preferences is the reference. The file `⋯` opens the same `AppContextMenu` as a right-click.

---

## Agent and automations

- **2026-08-07** — Agent/automation **run defaults** (`apply_mode`, etc.) live in [`shared/run_config.py`](system_app_back_end/shared/run_config.py). Call sites import them; do not re-hardcode fallbacks in routes, runner, or FE services. Consult sends `apply_mode` from the FE toggle; if omitted, backend `DEFAULT_MANUAL_APPLY_MODE` wins. FE automation create keeps a twin in `agent_run_defaults.dart`.
- **2026-08-16** — Pending agent reviews: the lookalike review opens on file mount; Finish archives a deep-copied old file then applies the merged agent text.
- **2026-08-07** — Production-agent **writing/editing guidance** must be written as short, structured **instructions** (numbered steps, MUST / MUST NOT), not tip-style prose. The model already gets a lot of context; soft advice gets ignored. Scenario-specific jobs (e.g. “notes → update plan”) belong in topic/automation prompts, not in generic tool descriptions.
- **2026-07-31** — Agent interaction plan wrapped (after objects): [`working on the agent interaction.md`](working%20on%20the%20agent%20interaction.md). Responses API + per-flow conversation; scope + hints (file/date/…); tools `patch_file` / `rewrite_file`; pending reviews in DB; archive files read-only.

---

## History

One-time facts, kept for lookup — nothing to act on.

| Fact | Detail |
|------|--------|
| Migration `004` | Dropped `files.is_essence`; visibility comes from the layout. |
| Migration `006_object_graph.sql` | Object graph / tags / diagram — applied manually on the Render Postgres DB (`tags.icon`, `links.kind`, `links.anchor`). |
| Migration `007_table_object.sql` | Adds `table` to the type CHECK, migrates legacy `graph` rows. |
| Migration `008_agent_pending_reviews.sql` | Pending agent reviews table. |
| Checkpoint `f5034af` | Commit before the marker-text (v4) work. |
| `BlockDocumentEditor` removed | Multi-`TextField` editor replaced by Super Editor; legacy table fences migrate on open. |
