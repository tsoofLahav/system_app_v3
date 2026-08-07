# Working on the agent interaction

**Status:** Settled plan — implement **after** objects-in-files.  
Not day-to-day coding memory (`DEVELOPMENT.md` / `AREA.md`).

---

## Goal

Production agent finds the right files and makes accurate edits. User either reviews a git-merge-style diff, or the action applies silently.

Agent never touches `document_json`. It reads/writes **agent text**; backend converts both ways.

---

## Core rules (don’t reopen unless product changes)

| Topic | Decision |
|-------|----------|
| API | **Responses API** + one OpenAI conversation per workflow |
| Memory | DB = long-term; OpenAI conversation = short-term for that run only (no need to archive chats) |
| File format for agent | **Agent text** with fences; never raw JSON |
| Scope | Hard allow-list of topic/file ids (from UI). Not file bodies. |
| Hints | Tiny pointers on the first turn: focused file, selection, dates, etc. Not file bodies. |
| Content | Loaded only via tools (`open_file` / search) |
| Archive files | Readable when needed; **never writable** |
| Review vs apply | **Action config** (+ tool defaults). Model does not choose the dialog. |
| Pending reviews | Persisted in **our DB**; shown when user opens the topic/file. Accept/reject is separate from the agent run. |
| Diff | Agent text ↔ agent text only; look like the real file (read-only presentation) |

---

## Run flow (one workflow)

1. Frontend sends: **prompt** + **scope** + optional **hints**.
2. Backend creates OpenAI conversation; stores `conversation_id` + scope on workspace; attaches standing instructions once (`agent_configs.system_prompt`).
3. First message = prompt + scope (+ hints). No file bodies.
4. Loop: model calls tools → backend runs them (enforce scope; reject writes to archived) → send **tool results only** back into the same conversation.
5. Each write tool either **applies to DB** or **queues a pending change** (per action config).
6. Run ends. Drop the OpenAI conversation. Pending reviews + any compact undo stay in DB.
7. Later, user opens topic/file → sees pending reviews → accept/reject → apply via `apply_agent_text` (independent of the chat).

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
| **`move_text`** | **Place** user content (find topic/file/spot; insert) | Content + destination anchor | Usually apply |
| **`patch_file`** | **Update** existing content in place | Exact `old_text` → `new_text` replacements (unique) | Review / pending |
| **`rewrite_file`** | True whole-file rewrite | Full new agent text | Usually apply |

Tool choice is guided by accurate descriptions (and standing prompt) — not hard bans. `patch_file` must not rewrite the whole file: only matched spans change, so blank lines and other whitespace outside hunks stay identical for the future side-by-side diff.

Read tools: `open_file`, `search`, object/task search.

---

## Pending review + undo

| Path | Behaviour |
|------|-----------|
| **Review** | Don’t write live file. Store pending change (file id, old/new agent text, run id). Diff UI later. |
| **Apply** | Write now. Keep **compact undo** sized to the change (reverse hunk for tiny; fuller snapshot for rewrite). |

Multi-file runs: each write applies or queues on its own; accumulate pending records in DB (not only in the HTTP response).

---

## Diff UI

1. Line-level diff on agent text (incl. fences).
2. Word-level marks inside changed lines.
3. Side-by-side; read-only presentation that **looks** like the file (shared styles with editor; no live edit widgets).
4. Accept/reject → merged agent text → `apply_agent_text`.

```
agent text  →  presentation blocks  →  read-only UI
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

1. **Runner** — Responses API + per-flow `conversation_id` / workspace (scope, hints, workflow metadata). Tool loop = tool results only.
2. **`open_file`** — agent text + minimal extras; archive files read-only for writes.
3. **Fences** — freeze task / info / image / graph agent-text shapes; align prompt.
4. **Write tools** — `patch_file`, `move_text`, `rewrite_file`; action-config apply vs review.
5. **Pending changes** — DB records + accept/reject API (decoupled from OpenAI conversation).
6. **Presentation + diff UI** — read-only lookalike; line + word; open from topic/file when pending exists.
7. **Compact undo** — reverse hunk / sized snapshot for applied writes.
8. **Prompt** — trim, sync to DB, smoke-test a few actions.

---

## Out of scope

- Model reading/writing raw `document_json`
- Storing agent text as a DB column
- Editable rich text inside diff panes
- Fat object ORM dumps in the prompt
- Archiving OpenAI conversations as product memory or undo
