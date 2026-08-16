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

That file is **for the model**: short standing instructions in four parts — what this is, tools, input, workflow. Keep it instructional and short; drop vague lines the model cannot act on. Bulky fence/tool **examples** live in [`content/production_agent/reference.md`](../../../content/production_agent/reference.md) and are loaded on demand via the `reference` tool (`agent_text` | `tools` | `all`). Maintainer notes stay in this `AREA.md`. Scenario-specific jobs belong in topic/automation prompts later — not in generic tool descriptions.

## What is passed to the agent

| Piece | Contents |
|-------|----------|
| **instructions** | `agent_configs.system_prompt` + operational suffix (attached on each Responses turn) |
| **First user input** | `prompt` + client `scope` (open topic/files as context) + optional tiny `hints` — **no file bodies** |
| **Tools** | `list`, `find_file`, `find_object`, `open_file`, `create_object`, `reference`, `patch_file`, `rewrite_file` |
| **Follow-up input** | Tool results only (`function_call_output` items) |

Tools authorize by **workspace membership** (run `workspace_id`), not the FE allow-list. Client `scope` / `hints` are preferred context (`focused_file_id`, open topic). Archived files stay read-only on writes.

`hints` are optional pointers on the first turn only (e.g. `focused_file_id`, `selected_text`, `for_date`). Never dump file content there.

## Run loop (Responses API)

```
create OpenAI conversation
  → responses.create(instructions, tools, prompt+scope+hints)
  → while function_call items:
        run tools (workspace membership; reject archived writes)
        responses.create(tool results only)
  → plain-text summary
delete conversation
```

Short-term memory is the OpenAI conversation for that run only. It is dropped when the run ends. Pending reviews live in `agent_pending_reviews`.

## Tools

| Tool | Behavior |
|------|----------|
| `list` | Topics, or files / objects **grouped by topic** (optional `topic_id`) |
| `find_file` | By `file_id`, or name (+ optional topic); hits include the topic name |
| `find_object` | By `object_id`, or type/name (+ optional topic); hits include file + topic name |
| `open_file` | Returns `name` + `topic`, `document_plain` (agent text), `document_lines` (1-based), + `object_extras`. Archived readable. |
| `create_object` | Create embed + pointer (`task_list` \| `info` \| `table` \| `graph` \| `image`); returns `object_id` |
| `reference` | On-demand examples from `content/production_agent/reference.md` (`agent_text` / `tools` / `all`) |
| `patch_file` | **Partial edits** with `op` add / remove / replace on `document_lines`; typical outcome **review** |
| `rewrite_file` | Full new agent text for a true whole-file rewrite; typical outcome **apply** when run allows |

**Everything the agent browses is keyed by topic name, never by a bare `topic_id`.** A file name on its own ("log", "plan") does not say what it is about, so `list files` / `list objects` return `topics: [{topic_id, topic, files: […]}]` and every `find_*` hit repeats its topic name. Choosing a topic is the first decision the agent makes; leaving it to guess from file names put a nutrition note in the wrong topic.

Browse helpers: [`services/browse_tools.py`](services/browse_tools.py). Create: [`services/create_object_tool.py`](services/create_object_tool.py) + shared [`areas/objects/services/create_embed.py`](../objects/services/create_embed.py). `open_file` payload: [`services/open_file_tool.py`](services/open_file_tool.py). Writes: [`services/write_tools.py`](services/write_tools.py).

**Apply vs review:** the run’s `apply_mode` wins (`review` / `direct_apply` / `notify_only`). Defaults live in **one place**: [`shared/run_config.py`](../../shared/run_config.py) (`DEFAULT_MANUAL_APPLY_MODE`, `DEFAULT_AUTOMATION_APPLY_MODE`). Routes/runner/models import those — do not hardcode fallback strings. Manual **Consult** sends `apply_mode` from the FE toggle (default review). Automations store their own mode. The model does not choose the dialog.

The agent never sees or writes raw JSON. It reads and writes **agent text**; the [files area](../files/AREA.md) converts in both directions.

Each write tool ends in the same apply path (`patch_file` / `rewrite_file`):

1. Build new agent text (`patch_file` line edits / `rewrite_file` full text)
2. Parse agent text → v4 editor text + object payload updates (`apply_agent_text_to_file`)
3. Reject if any embed `object_id` is unknown or was dropped; reject id-less `[TABLE]` on write
4. Reject archived files
5. On `direct_apply` (and Accept via API): `commit_agent_file_apply` — promote legacy embeds → file version → `document_json` → `object_updates` → purge unreferenced embeds

`create_object` allocates a real embed id and inserts the pointer (shared with `POST /files/:id/objects`); fill content afterward with `patch_file`.

## Apply modes

| Mode | Effect |
|------|--------|
| `direct_apply` | Writes immediately via `commit_agent_file_apply`, commits; response includes per-file `undo` card (old snapshot + change previews) for the FE toast |
| `review` | Rolls back live writes; upserts `agent_pending_reviews`; response includes `has_pending_review` |
| `notify_only` | Returns the new document without diff or write |

## Pending reviews

Table `agent_pending_reviews` (one open row per `file_id`; newest run replaces). After review rollback, runner upserts then commits.

| Method | Path | Role |
|--------|------|------|
| GET | `/files/:id/pending-review` | `{ pending: null \| { …, hunks } }` |
| POST | `/files/:id/pending-review/finish` | Per-hunk decisions → archive deep-copy of old file → apply merged agent text → delete pending |
| DELETE | `/files/:id/pending-review` | Discard |

Finish archives as `"{name} (before AI · {local date})"` with deep-copied embeds, then `apply_agent_text` on the live file. `create_object` proposals are not queued for line-merge pending (direct_apply only this pass).

Hunks come from agent-text `SequenceMatcher`, with **adjacent delete+insert coalesced into replace** so an edit never applies as “keep old + insert new”. Merge walks the same normalized opcodes: add inserts, remove deletes, change replaces.

Service: [`services/pending_reviews.py`](services/pending_reviews.py).

## Diff logic (review mode)

Diffs are computed on **agent text**, not JSON — a JSON diff is unreadable and noisy.

```
old document_json ─┐
                   ├─ document_to_agent_text (embeds expanded) ─→ unified / hunks
new document_json ─┘
```

Tool results still include `{ diff_hunks, old_document_text, new_document_text }` for debugging. The product path is pending DB + lookalike UI. `POST /files/:id/apply-agent-text` remains for direct apply / finish.

The same `compute_diff` backs `POST /files/:id/diff`.

## Modules

| Module | Role |
|--------|------|
| [`services/runner.py`](services/runner.py) | Conversation lifecycle, tool dispatch, pending upsert after review rollback |
| [`services/pending_reviews.py`](services/pending_reviews.py) | Hunks, merge, archive copy, finish/discard |
| [`services/write_tools.py`](services/write_tools.py) | `patch_file` / `rewrite_file`, `commit_agent_file_apply`, diff, mode resolution |
| [`services/open_file_tool.py`](services/open_file_tool.py) | `open_file` payload (agent text + extras) |
| [`services/prompt.py`](services/prompt.py) | Load/seed/sync the system prompt from the DB |
| [`services/openai_service.py`](services/openai_service.py) | Responses conversation helpers + legacy chat/image helpers |
| [`routes/agent.py`](routes/agent.py) | `POST /agent/run`; apply-agent-text; pending-review routes |

## Rules

- Scope is preferred context — tools authorize by workspace membership.
- Never put file bodies in the first turn; load only via tools.
- Follow-up turns send tool results only.
- Never persist agent text as the live file format.
- Never apply a partial update: if parsing produced errors, write nothing.
- `review` and `notify_only` must roll back the tool session; review then persists pending in a new commit.
- Drop the OpenAI conversation when the run ends.
- Changing the agent's behavior means editing the markdown source and syncing — not hardcoding prompt text in `runner.py`.

## Known gaps (later)

- Undo for `create_object` alone / long-lived DB undo
- Per-hunk review of `create_object`
- `agent_configs.tool_allowlist` is not yet honored
