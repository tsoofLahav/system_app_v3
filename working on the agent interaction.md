# Working on the agent interaction

**Status:** Pending DB + PR-style lookalike review + Consult toggle + **compact undo toast for direct_apply** are implemented. Prompt polish (step 8) ongoing.  
Not day-to-day coding memory (`DEVELOPMENT.md` / `AREA.md`).

---

## Goal

Production agent finds the right files and makes accurate edits. User either reviews a lookalike per-hunk diff when opening the file, or the action applies silently.

Agent never touches `document_json`. It reads/writes **agent text**; backend converts both ways.

---

## Core rules (don’t reopen unless product changes)

| Topic | Decision |
|-------|----------|
| API | **Responses API** + one OpenAI conversation per workflow |
| Memory | DB = long-term; OpenAI conversation = short-term for that run only (no need to archive chats) |
| File format for agent | **Agent text** with fences; never raw JSON |
| Scope | Preferred topic/file context from UI (not a hard tool allow-list). Not file bodies. |
| Hints | Tiny pointers on the first turn: focused file, selection, dates, etc. Not file bodies. |
| Content | Loaded only via tools (`open_file` / list / find) |
| Browsing | Always **by topic**: `list files` / `list objects` group under `{topic_id, topic}`, `find_*` hits and `open_file` name their topic. The agent picks the topic before the file. |
| Archive files | Readable when needed; **never writable** |
| Review vs apply | **Action config** (+ Consult toggle). Model does not choose the dialog. |
| Pending reviews | Persisted in **`agent_pending_reviews`**; lookalike UI when user opens the file. Finish archives old copy then applies merge. |
| Diff | Agent text ↔ agent text only; look like the real file (read-only presentation) |

---

## Run flow (one workflow)

1. Frontend sends: **prompt** + **scope** + optional **hints** (+ Consult `apply_mode`).
2. Backend creates OpenAI conversation; stores `conversation_id` + scope on workspace; attaches standing instructions once (`agent_configs.system_prompt`).
3. First message = prompt + scope (+ hints). No file bodies.
4. Loop: model calls tools → backend runs them (workspace auth; reject writes to archived) → send **tool results only** back into the same conversation.
5. Each write tool either **applies to DB** or **queues a pending change** (per action config).
6. Run ends. Drop the OpenAI conversation. Pending reviews stay in DB.
7. Later, user opens file → lookalike hunk dialog → accept/reject each → Finish → archive copy + `apply_agent_text`.

### Hints (first turn only)

Small pointers so “this” / “today” aren’t guesses. Examples:

- `focused_file_id`, `selected_text`
- automation: `for_date`, other action params

Omit when unused. Extend the set as actions need — keep them tiny.

---

## What `open_file` returns

1. Expand `document_json` + related objects into **agent text** (fences: `[TASK_LIST]`, `[INFO]`, …).
2. Add only **minimal type-specific extras** when useful (e.g. info **Links:** id + title/type). No ORM dumps.
3. Teach object/id/links once in the system prompt; same words in payload and prompt.

| Type | In fence | Extra |
|------|----------|-------|
| Task list | Checkbox lines + titles | usually none |
| Info | Title + body | Links if any |
| Image | Caption / ref | usually none |
| Graph | Variable/value table (+ type/color if needed) | usually none |

---

## Write tools

| Tool | When | Model sends | Typical outcome |
|------|------|-------------|-----------------|
| **`patch_file`** | **Partial edits** add / remove / replace by line | `op`, `line`, `end_line`, `text` | Review / pending |
| **`rewrite_file`** | True whole-file rewrite | Full new agent text | Usually apply |
| **`create_object`** | New embed + pointer | type + fields | **direct_apply** this pass (not line-merge pending) |

Tool choice is guided by accurate descriptions (and standing prompt) — not hard bans. `patch_file` uses exact replacements so unchanged spans stay intact. Extra blank lines map in the **mapper only** as `[SPACER n="…"]` ↔ empty paragraphs / blank runs in paragraph text (no editor spacer type).

Browse: `list`, `find_file`, `find_object`, `open_file`, `reference`.

---

## Pending review + undo

| Path | Behaviour |
|------|-----------|
| **Review** | Rollback live file. Upsert pending (file id, old/new agent text + document_json, run key). Lookalike UI on file open. Finish: deep-copy old into topic Archive, apply merged agent text to live file, delete pending. |
| **Apply** | Write now. Compact undo toast: file + topic + change summary; Undo restores `old_document_json`; X / ~8s dismiss; multi-file queued. |

Multi-file runs: each file gets its own pending row; each opens on that file.

---

## Diff UI

1. Full-file **side-by-side** (Current | Suggested); unchanged lines shown.
2. Contiguous line hunks; Accept/Reject per region.
3. Word-level marks inside changed lines; fences as compact chrome (read-only).
4. Opens on file mount; if that file is already on screen when the run finishes → open immediately.
5. Finish → merge (add / remove / **replace**, never keep-old+insert) → archive deep-copy → apply.

```
agent text  →  PR-style dual pane  →  decisions → merge → archive + apply
```

---

## Standing prompt

| Layer | Where |
|-------|--------|
| Git | [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) |
| Runtime | `agent_configs.system_prompt` |
| Sync | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |

Keep short: agent text + fences; object ids; tool choice; open/search when needed; never invent ids; never edit archived.

---

## Implementation steps (do in order)

1. **Runner** — Responses API + per-flow `conversation_id` / workspace (scope, hints, workflow metadata). Tool loop = tool results only. ✅
2. **`open_file`** — agent text + minimal extras; archive files read-only for writes. ✅
3. **Fences** — freeze task / info / image / graph agent-text shapes; align prompt. ✅
4. **Write tools** — `patch_file`, `rewrite_file`; action-config apply vs review. ✅
5. **Pending changes** — DB records + finish/discard API (decoupled from OpenAI conversation). ✅
6. **Presentation + diff UI** — lookalike; line + word; open from file when pending exists. ✅
7. **Compact undo** — reverse snapshot toast for applied writes. ✅
8. **Prompt** — trim, sync to DB, smoke-test a few actions. (ongoing)

---

## Out of scope

- Model reading/writing raw `document_json`
- Storing agent text as a DB column
- Editable rich text inside diff panes
- Fat object ORM dumps in the prompt
- Archiving OpenAI conversations as product memory or undo
