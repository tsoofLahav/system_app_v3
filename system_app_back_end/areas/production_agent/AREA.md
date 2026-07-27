# Area: Production agent (backend)

The runtime AI that reads and edits the user's files. Frontend counterpart: [`system_app_front_end/lib/areas/production_agent/AREA.md`](../../../system_app_front_end/lib/areas/production_agent/AREA.md).

**Not the coding agent.** Cursor/dev-agent guidance lives in [`DEVELOPMENT.md`](../../../DEVELOPMENT.md).

## The agent has its own markdown file

The agent's standing instructions are a real document it is allowed to read:

| Layer | Location |
|-------|----------|
| **Git source** (edit here) | [`content/production_agent/system_prompt.md`](../../../content/production_agent/system_prompt.md) |
| **Runtime source** (what the agent actually reads) | `agent_configs.system_prompt` in PostgreSQL |
| **Sync** | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |

Bootstrap seeds the DB row on first launch. The runner never reads the markdown file at request time — only the DB.

## What is passed to the agent

Every run sends two messages:

| Message | Contents |
|---------|----------|
| **system** | `agent_configs.system_prompt` + a fixed operational suffix (tool-call JSON contract) |
| **user** | `prompt`, `scope`, `context`, the workspace's topics, and the tool definitions |

`scope` limits what the agent can reach: `{ "topic_ids": [...] }` or `{ "file_ids": [...] }`. Nothing outside scope is searchable.

## Tools

| Tool | Behavior |
|------|----------|
| `search` | Substring match on file name and **agent text** within scope |
| `open_file` | Returns `document_plain` (agent text) plus the file's embedded objects |
| `update_file` | Full replacement — takes `document_text` in agent text format |
| `search_tasks` | Substring match on task titles |

The agent never sees or writes raw JSON. It reads and writes **agent text**; the [files area](../files/AREA.md) converts in both directions.

## Run loop

```
prompt → system + user message
  → up to 6 rounds of { "tool_calls": [...] }
  → { "final": "summary" }
```

Each `update_file` call:

1. Parse agent text → block tree + object payload updates
2. Reject if any embed `object_id` is unknown or was dropped
3. Save a file version
4. Write `document_json`, then apply object updates

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
| [`services/runner.py`](services/runner.py) | Tool dispatch, run loop, apply modes, diff |
| [`services/prompt.py`](services/prompt.py) | Load/seed/sync the system prompt from the DB |
| [`services/openai_service.py`](services/openai_service.py) | Model call returning JSON |
| [`routes/agent.py`](routes/agent.py) | `POST /agent/run` |

## Rules

- Scope is a hard boundary — never widen it inside a tool.
- Never persist agent text.
- Never apply a partial update: if parsing produced errors, write nothing.
- `review` and `notify_only` must roll back the session.
- Changing the agent's behavior means editing the markdown source and syncing — not hardcoding prompt text in `runner.py`.

## Known gaps

`agent_configs.model` and `agent_configs.tool_allowlist` exist but are not honored yet — the model and tool set are still fixed in code.
