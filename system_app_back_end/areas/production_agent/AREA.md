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
| **Sync (local)** | `python scripts/sync_agent_prompt.py --overwrite` |
| **Sync (Render)** | On web boot when `RENDER=true` — uses the service **internal** `DATABASE_URL` (`maybe_sync_prompts_on_boot`). Opt out with `SYNC_AGENT_PROMPT_ON_DEPLOY=0`. |

Bootstrap seeds the DB row on first launch. The runner never reads the markdown file at request time — only the DB. Deploying the backend refreshes the prompt over the internal DB link (no laptop → external Postgres needed).

That file is **for the model**: short system explainer + how to work + write-tool rules. Keep it instructional and short. Bulky fence/tool **examples** live in [`content/production_agent/reference.md`](../../../content/production_agent/reference.md) and are loaded on demand via the `reference` tool (`agent_text` | `tools` | `all`). Maintainer notes stay in this `AREA.md`. Scenario-specific jobs belong in topic/automation prompts later — not in generic tool descriptions.

## What is passed to the agent

| Piece | Contents |
|-------|----------|
| **instructions** | `agent_configs.system_prompt` + operational suffix (attached on each Responses turn) |
| **First user input** | `prompt` + hard `scope` + optional tiny `hints` — **no file bodies** |
| **Tools** | Native Responses function tools (`search`, `open_file`, `reference`, `patch_file`, `rewrite_file`, `search_tasks`) |
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
| `reference` | On-demand examples from `content/production_agent/reference.md` (`agent_text` / `tools` / `all`) |
| `patch_file` | **All partial edits** (change / delete / add lines, including inside embed fences) via exact unique `old_text` → `new_text`; typical outcome **review** |
| `rewrite_file` | Full new agent text for a true whole-file rewrite; typical outcome **apply** when run allows |
| `search_tasks` | Substring match on task titles within scoped (live) files |

`open_file` payload: [`services/open_file_tool.py`](services/open_file_tool.py). Writes: [`services/write_tools.py`](services/write_tools.py).

**Apply vs review:** the run’s `apply_mode` wins (`review` / `direct_apply` / `notify_only`). Defaults live in **one place**: [`shared/run_config.py`](../../shared/run_config.py) (`DEFAULT_MANUAL_APPLY_MODE`, `DEFAULT_AUTOMATION_APPLY_MODE`). Routes/runner/models import those — do not hardcode fallback strings. Manual consult currently defaults to `direct_apply` until the real diff UI ships. Automations store their own mode. The model does not choose the dialog.

The agent never sees or writes raw JSON. It reads and writes **agent text**; the [files area](../files/AREA.md) converts in both directions.

Each write tool ends in the same apply path:

1. Build new agent text (`patch_file` replacements / `rewrite_file` full text)
2. Parse agent text → v4 editor text + object payload updates (`apply_agent_text_to_file`)
3. Reject if any embed `object_id` is unknown or was dropped; reject id-less `[TABLE]` on write
4. Reject archived files
5. On `direct_apply` (and Accept via API): `commit_agent_file_apply` — promote legacy embeds → file version → `document_json` → `object_updates` → purge unreferenced embeds

## Apply modes

| Mode | Effect |
|------|--------|
| `direct_apply` | Writes immediately via `commit_agent_file_apply`, commits |
| `review` | Returns proposed change with `object_updates` + `review` diff; rolls back live file |
| `notify_only` | Returns the new document without diff or write |

## Diff logic (review mode)

Diffs are computed on **agent text**, not JSON — a JSON diff is unreadable and noisy.

```
old document_json ─┐
                   ├─ document_to_agent_text (embeds expanded) ─→ unified diff
new document_json ─┘
```

Returns `{ diff_hunks, old_document_text, new_document_text }`. The review tool result also includes `object_updates`. The frontend Accept path calls `POST /files/:id/apply-agent-text` with `document_json` + `object_updates` (not a bare file PATCH).

The same `compute_diff` backs `POST /files/:id/diff`.

## Modules

| Module | Role |
|--------|------|
| [`services/runner.py`](services/runner.py) | Conversation lifecycle, tool dispatch |
| [`services/write_tools.py`](services/write_tools.py) | `patch_file` / `rewrite_file`, `commit_agent_file_apply`, diff, mode resolution |
| [`services/open_file_tool.py`](services/open_file_tool.py) | `open_file` payload (agent text + extras) |
| [`services/prompt.py`](services/prompt.py) | Load/seed/sync the system prompt from the DB |
| [`services/openai_service.py`](services/openai_service.py) | Responses conversation helpers + legacy chat/image helpers |
| [`routes/agent.py`](routes/agent.py) | `POST /agent/run`; `POST /files/:id/apply-agent-text` |

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

- Pending reviews are still returned in the HTTP response, not yet persisted independently in DB (step 5).
- `agent_configs.tool_allowlist` is not yet honored.
