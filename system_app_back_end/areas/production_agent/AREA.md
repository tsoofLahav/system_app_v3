# Area: Production agent (backend)

The runtime AI that reads and edits the user's files. Frontend counterpart: [`system_app_front_end/lib/areas/production_agent/AREA.md`](../../../system_app_front_end/lib/areas/production_agent/AREA.md).

**Not the coding agent.** Cursor/dev-agent guidance lives in [`DEVELOPMENT.md`](../../../DEVELOPMENT.md).

Interaction plan: [`working on the agent interaction.md`](../../../working%20on%20the%20agent%20interaction.md).

## The agent has its own markdown file

The agent's standing instructions are a real document it is allowed to read:

| Layer | Location |
|-------|----------|
| **Git source** (edit here) | [`content/production_agent/system_prompt.md`](../../../content/production_agent/system_prompt.md) |
| **Runtime source** (what the agent actually reads) | `agent_configs.system_prompt` in PostgreSQL |
| **Sync** | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |

Bootstrap seeds the DB row on first launch. The runner never reads the markdown file at request time — only the DB.

## What is passed to the agent

| Piece | Contents |
|-------|----------|
| **instructions** | `agent_configs.system_prompt` + operational suffix (attached on each Responses turn) |
| **First user input** | `prompt` + hard `scope` + optional tiny `hints` — **no file bodies** |
| **Tools** | Native Responses function tools (`search`, `open_file`, `update_file`, `search_tasks`) |
| **Follow-up input** | Tool results only (`function_call_output` items) |

`scope` is a hard allow-list: `{ "topic_ids": [...] }` and/or `{ "file_ids": [...] }`. Empty scope is rejected.

`hints` are optional pointers on the first turn only (e.g. `focused_file_id`, `selected_text`, `for_date`). Never dump file content there.

## Run loop (Responses API)

```
create OpenAI conversation
  → responses.create(instructions, tools, prompt+scope+hints)
  → while function_call items:
        run tools (enforce scope; reject archived writes)
        responses.create(tool results only)
  → plain-text summary
delete conversation
```

Short-term memory is the OpenAI conversation for that run only. It is dropped when the run ends. Pending reviews / undo stay in our DB (later steps).

## Tools

| Tool | Behavior |
|------|----------|
| `search` | Substring match on file name and **agent text** within scope (includes archived, flagged) |
| `open_file` | Returns `document_plain` (agent text) + `object_extras` (info `title` / `Links` when useful). Archived readable. |
| `update_file` | Full replacement — takes `document_text` in agent text format; rejects archived |
| `search_tasks` | Substring match on task titles within scoped (live) files |

`open_file` payload shape is built by [`services/open_file_tool.py`](services/open_file_tool.py) — no ORM dumps.

The agent never sees or writes raw JSON. It reads and writes **agent text**; the [files area](../files/AREA.md) converts in both directions.

Each `update_file` call:

1. Parse agent text → block tree + object payload updates
2. Reject if any embed `object_id` is unknown or was dropped
3. Reject archived files
4. Save a file version (direct apply only)
5. Write `document_json`, then apply object updates

## Apply modes

| Mode | Effect |
|------|--------|
| `direct_apply` | Writes immediately, commits |
| `review` | Computes a diff, returns it as a proposed change, rolls back |
| `notify_only` | Returns the new document without diff or write |

## Diff logic (review mode)

Diffs are computed on **agent text**, not JSON — a JSON diff is unreadable and noisy.

```
old document_json ─┐
                   ├─ document_to_agent_text (embeds expanded) ─→ unified diff
new document_json ─┘
```

Returns `{ diff_hunks, old_document_text, new_document_text }`. The frontend renders `diff_hunks` in the review dialog and applies `new_document_json` only if the user accepts.

The same `compute_diff` backs `POST /files/:id/diff`.

## Modules

| Module | Role |
|--------|------|
| [`services/runner.py`](services/runner.py) | Conversation lifecycle, tool dispatch, apply modes, diff |
| [`services/open_file_tool.py`](services/open_file_tool.py) | `open_file` payload (agent text + extras) |
| [`services/prompt.py`](services/prompt.py) | Load/seed/sync the system prompt from the DB |
| [`services/openai_service.py`](services/openai_service.py) | Responses conversation helpers + legacy chat/image helpers |
| [`routes/agent.py`](routes/agent.py) | `POST /agent/run` (`prompt`, `scope`, `hints`, `apply_mode`) |

## Rules

- Scope is a hard boundary — never widen it inside a tool.
- Never put file bodies in the first turn; load only via tools.
- Follow-up turns send tool results only.
- Never persist agent text.
- Never apply a partial update: if parsing produced errors, write nothing.
- `review` and `notify_only` must roll back the session.
- Drop the OpenAI conversation when the run ends.
- Changing the agent's behavior means editing the markdown source and syncing — not hardcoding prompt text in `runner.py`.

## Known gaps (later plan steps)

- Write tools still use `update_file` (pending `patch_file` / `move_text` / `rewrite_file`).
- Pending reviews are still returned in the HTTP response, not yet persisted independently in DB.
- `agent_configs.tool_allowlist` is not yet honored.
