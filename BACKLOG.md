# Backlog — known unresolved issues

Everything here is a real, confirmed problem. Nothing here is speculative.

**Grouped by area so one area can be cleared at a time.** Inside each area, worst first.

Source: full-codebase review on 2026-07-27, after the area reorganization. None of these were caused by that reorganization — all predate it.

Severity key: **P1** breaks or corrupts data · **P2** wrong behavior the user will hit · **P3** cleanup and robustness.

---

## Files — backend (agent text)

Spec: [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) · Code: [`areas/files/services/document_agent_text.py`](system_app_back_end/areas/files/services/document_agent_text.py)

| # | Sev | Issue |
|---|-----|-------|
| F1 | **P1** | `direct_apply` assigns `file.document_json` *before* `apply_object_updates` runs, and `run_agent` commits without checking tool results for `error`. A failed object update still persists the new document. |
| F2 | **P1** | Legacy embeds (`object_id` null) serialize to `[IMAGE url="…"]` / `[GRAPH]`, which the parser cannot read, and the agent path never calls `promote_legacy_embeds`. Those blocks are silently dropped on apply. |
| F3 | **P1** | `_escape_cell` escapes `\` and `\t` but not `\n`. A newline inside a table cell becomes an extra row on read. |
| F4 | **P1** | An unmatched fence marker in ordinary text advances one character without emitting it, so `Hello [TABLE] world` loses characters. Affects `[TASK_LIST`, `[INFO`, `[IMAGE`, `[GRAPH`, `[BULLET_LIST`, `[ORDERED_LIST`, `[TABLE]`. |
| F5 | **P1** | `_sync_task_list` archives every existing task and inserts new rows. Task ids churn on each apply and `view_task_memberships` end up pointing at archived tasks. Contradicts "a task exists once". |
| F6 | **P2** | Malformed list/task lines are skipped with `continue`. `* [ ]` or `- []` vanish and the apply reports success. |
| F7 | **P2** | Spans are dropped on parse, so any agent edit clears inline formatting across the whole file, not just edited blocks. Intentional today, but it is real data loss — needs a merge strategy. |
| F8 | **P2** | Duplicate `[TASK_LIST id="42"]` pointer lines are not rejected; both stay in editor text and the last object update wins. |
| F9 | **P2** | A paragraph part whose text contains `\n\n` splits into two top-level parts on reindex/round-trip. Soft breaks should stay `\n` inside one part. |
| F10 | **P2** | Search calls `document_to_agent_text` without `objects_by_id`, so task-list and info content is invisible to search. |
| F11 | **P3** | Unescaped `"` in an IMAGE caption or GRAPH title produces an unparseable marker (then hits F4). |
| F12 | **P3** | `[/INFO]` or `[/TASK_LIST]` appearing inside a body truncates the match early (non-greedy `.*?`). |
| F13 | **P3** | Whitespace-only table rows are dropped on parse — a row of empty cells serializes to `\t` and `.strip()` treats it as blank. |
| F14 | **P3** | Indent is `leading // 2`, so a 1-space indent collapses to 0. |
| F15 | **P3** | Empty lists/tables/paragraphs are skipped on serialize and lost on round-trip, with no error. |
| F16 | **P3** | `_sync_task_list` / `_sync_info` return silently when `task_list_id` / `information_id` is null, after the document was already replaced. |
| F17 | **P3** | `_dispatch_tool` has no try/except; `int(args["file_id"])` on a missing key becomes a generic 500. |
| F18 | **P3** | Part/view ids are regenerated when folding agent apply through parse (not persisted in v4 text). Fine only while nothing keys off them. |

**Test gaps:** no coverage for ordered-list round-trip, nested lists, newlines in cells, span survival, legacy embeds, duplicate embeds, malformed task lines, quotes in captions, `direct_apply` rollback, or task-id preservation.

---

## Files — frontend (editor)

Code: [`areas/files/`](system_app_front_end/lib/areas/files/)

| # | Sev | Issue |
|---|-----|-------|
| ~~E1~~ | — | ~~Text is not continuous.~~ **Done.** `DocumentTextFlow` gives the file one caret and one selection across paragraphs, bullets, and cells. See the files [`AREA.md`](system_app_front_end/lib/areas/files/AREA.md). Remaining pieces are E4–E6 below. |
| ~~E4~~ | — | ~~Deleting across parts keeps the bullets and rows it passed through.~~ **Done.** A part marked end to end is removed, and a list or table whose every part was marked goes with it. Rules and their single implementation: [`document_structure_prune.dart`](system_app_front_end/lib/areas/files/editor/document_structure_prune.dart). Merging the first and last part is still open, as E8. |
| E5 | **P2** | Undo/redo is per document mutation and is not a single stack shared with cross-part edits. |
| E6 | **P3** | Embeds are not segments in the flow, so the caret jumps over an object instead of stepping into it. Expected — objects are a later section. |
| ~~E7~~ | — | ~~Two kinds of marking: actions hit only the right-clicked part.~~ **Done.** `DocumentMark` is the single target for every action — the marking when there is one, else the caret's line. |
| E8 | **P3** | Deleting across parts does not merge the first and last part into one. Both survive with their remaining text, where a word processor would join them. |
| E9 | **P3** | Cmd+arrow and Home/End still use the platform's logical direction, so in Hebrew they move against the arrow. Plain and Alt+arrow are fixed via intent overrides; line-break motion is shared with Home/End, so flipping it would break those. |
| E10 | **P3** | Text direction comes from the UI language, not from the text. A Hebrew paragraph in an English-UI file gets LTR caret behavior. Matches the app-wide rule in [`BILINGUAL.md`](system_app_front_end/lib/core/l10n/BILINGUAL.md); revisit if files become genuinely mixed. |
| E11 | **P3** | `BlockDocumentEditor.build` calls `_flow.setOrder`, which notifies from inside build. Harmless today because every listener is a descendant that has not been built yet this frame, but a listener added anywhere else would throw *markNeedsBuild during build*. |
| E2 | **P3** | `RichListEditor._localStateMatchesNode` compares text only, not spans, so an external span-only change (undo, remote sync) does not resync controllers. |
| E3 | **P3** | `RichTableEditor._focusNodes` grows via `_focusAt` and is never pruned when rows or columns shrink. Minor leak until the block is disposed. |

---

## Automations

Code: [`areas/automations/`](system_app_back_end/areas/automations/) · Cron: [`scripts/run_automations.py`](system_app_back_end/scripts/run_automations.py)

| # | Sev | Issue |
|---|-----|-------|
| A1 | **P1** | **Scheduling does not work.** The cron runs every enabled automation every minute and never reads `schedule`, `timezone`, or `next_run_at`. Each automation fires ~1,440 times a day, each one a paid agent call. |
| A2 | **P2** | `next_run_after()` in `automation_schedule.py` is fully implemented and timezone-aware, but nothing calls it. Wiring it into the cron is the fix for A1. |
| A3 | **P2** | The cron path never sets `last_run_at` or `finished_at`, unlike `POST /automations/:id/run`. Run history is incomplete for scheduled runs. |
| A4 | **P3** | Event triggers are stored in `trigger` (JSONB) but never dispatched — schedule is the only live trigger. |

---

## Objects

Code: [`areas/objects/`](system_app_back_end/areas/objects/) · Frontend data/views: [`lib/areas/objects/`](system_app_front_end/lib/areas/objects/) · In-file embeds: [`lib/areas/files/editor/embeds/`](system_app_front_end/lib/areas/files/editor/embeds/)

| # | Sev | Issue |
|---|-----|-------|
| O1 | **P1** | Task identity is destroyed by agent applies (see F5). `view_task_memberships` survive pointing at archived tasks. Fixing F5 fixes this. |
| O2 | **P2** | Tag mutation is unreachable from the app: `POST /tags`, `DELETE /tags/:id`, and `POST`/`DELETE /tags/assign` have no frontend caller, so topics cannot actually be tagged. Tags are the v3 replacement for hardcoded topic types. |
| O3 | **P2** | Nested caret inside object fields is not yet linked to `DocumentTextFlow` as segments — Exit-below bridges work; full in-flow segments remain. |
| O4 | **P2** | Convert selected text → Info / list → Task list helpers exist in `AppState` but have no UI entry. |
| O5 | **P3** | Image resize handles are not built; width lives in payload only. |
| ~~O6~~ | — | ~~Agent graph markers omit labels/values.~~ **Done** — `_graph_section` expands the full table. |

---

## Production agent

Code: [`areas/production_agent/`](system_app_back_end/areas/production_agent/)

| # | Sev | Issue |
|---|-----|-------|
| P1 | **P2** | Review/diff is half-wired: the frontend reads `diff_hunks` off the agent response but never calls `POST /files/:id/diff` or `GET /files/:id/versions`. There is no version-history UI. |
| P2 | **P3** | `ensure_agent_config` calls `load_prompt_file()` for a new workspace with no fallback. If `content/production_agent/system_prompt.md` is missing at runtime, bootstrap and `/agent/run` raise. |

---

## UI — style debt

Code: [`areas/ui/`](system_app_front_end/lib/areas/ui/) · Spec: [`areas/ui/AREA.md`](system_app_front_end/lib/areas/ui/AREA.md)

The spec says every visual constant lives in `areas/ui/`. These are the places that is not yet true.

| # | Sev | Issue |
|---|-----|-------|
| U1 | **P3** | `app_context_menu.dart` and `details_hover_bubble.dart` keep their own visual language: local blur and tint values instead of an `AppGlassStyle` preset, and their own shadow stacks. |
| U2 | **P3** | `change_review_dialog.dart` and `text_diff_dialog.dart` bypass `AppGlassDialog` and `AppTypography` — raw `TextStyle(fontSize: 18)`, `fontFamily: 'monospace'`, own max sizes. |
| U3 | **P3** | Document heading sizes are computed inline as `24 - level * 2` in `block_document_editor.dart` instead of being named styles in `AppTypography`. |
| U4 | **P3** | Material `Icons.*` still appear among the Lucide set (`task_mark`, `task_row`, `task_view_pane`, `automation_dialog`, `ai_tool_bar`), so stroke weights do not match. |
| U5 | **P3** | `AppSwitch` is defined and themed but no widget uses it; `BILINGUAL.md` describes it as standard. Either adopt it or drop it. |

---

## Cleanup (any time)

| # | Sev | Issue |
|---|-----|-------|
| C1 | **P3** | ~30 Dart files under `lib/` are unreachable from `main.dart` — leftovers from v1 (`part.dart`, `brought_file_snapshot.dart`, `automation_rule.dart`, and more). Old `list_block_widget` / `table_block_widget` / `document_undo_stack` / `document_body.py` removed in the post-v4 cleanup. |
| ~~C2~~ | — | ~~`document_body.py` dead re-export.~~ **Done** — deleted. |
| C3 | **P3** | 35 analyzer warnings, all `dead_null_aware_expression` / `dead_code` from `??` applied to non-nullable `AppStrings` getters. |

---

## Related

| Doc | Purpose |
|-----|---------|
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Working memory, area map, deploy loop |
| [`system_app_back_end/areas/files/AREA.md`](system_app_back_end/areas/files/AREA.md) | Agent-text gaps in context |
| [`system_app_back_end/areas/automations/AREA.md`](system_app_back_end/areas/automations/AREA.md) | Automation gaps in context |
