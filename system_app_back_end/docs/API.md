# API Reference (v2)

REST endpoint reference. Behavior and rules live in the area docs: [`areas/README.md`](../areas/README.md).

All endpoints return JSON. Timestamps are ISO 8601 strings.

## Error format

```json
{"error": "description"}
```

| Status | When |
|--------|------|
| 400 | Validation error |
| 404 | Resource not found |
| 500 | Server error |

Successful DELETE returns `204` with empty body.

---

## Health

| Method | Path | Response |
|--------|------|----------|
| GET | `/health` | `{"status": "ok"}` |

---

## Bootstrap

| Method | Path | Description |
|--------|------|-------------|
| POST | `/bootstrap` | Create default workspace, home topic, Daily essence file if DB empty |
| GET | `/bootstrap/status` | `{"ready": true, "workspace_id": 1}` |

---

## Workspaces

| Method | Path | Description |
|--------|------|-------------|
| GET | `/workspaces` | List |
| GET | `/workspaces/<id>` | Get one |
| POST | `/workspaces` | Create `{ "name": "..." }` |

---

## Topics

| Method | Path | Description |
|--------|------|-------------|
| GET | `/topics` | List (`?workspace_id=`) |
| GET | `/topics/<id>` | Get one |
| GET | `/topics/<id>/task-lists` | Task-list objects in live files of that topic |
| POST | `/topics` | Create |
| PATCH | `/topics/<id>` | Update |
| DELETE | `/topics/<id>` | Delete cascade |

**POST body:** `{ "workspace_id", "name", "icon?", "color?", "order_index?", "file_layout?" }`

**PATCH:** `name`, `icon`, `color`, `order_index`, `file_layout`, `archived_at`

`file_layout` is how the topic arranges its files on screen (`auto`, `single`, `split`, `hero`, `grid`). `auto` follows file count (1 → single, 2 → split, 3+ → three-file hero) until the user picks a layout. Leftover `hero_left` / `hero_right` / `row` still load. It also decides how many files are shown at all — see [files area](../areas/files/AREA.md).

---

## Files

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files` | List all |
| GET | `/files/<id>` | Get one (includes `body`) |
| GET | `/files/<id>/agent-text` | Expanded agent text (archived files included) |
| GET | `/topics/<topic_id>/files` | Files for topic |
| GET | `/topics/<topic_id>/archive/files` | Paginated archived files (`limit`, `offset`, `q`) — no `document_json` |
| POST | `/files` | Create |
| POST | `/files/<id>/apply-snippet` | `{ document_json, objects, append? }` — clone snippet objects and write (replace, or append when `append` is true) |
| PATCH | `/files/<id>` | Update (name, body, order_index, meta, archived_at) |
| DELETE | `/files/<id>` | Delete cascade |

**POST body:** `{ "topic_id", "name", "body?", "order_index?", "meta?" }`

Archive list response: `{ "files", "total", "has_more", "heading_texts_by_file_id" }`. Cards omit `document_json`. Search (`q`) matches the file name or `#`…`######` heading lines in the marker body, not expanded objects. `limit=0` returns the count only (used by the sidebar index). Preview a body with `GET /files/<id>/agent-text` (`{ "agent_text" }`), including archived files. `PATCH` `{ "archived_at": null }` unarchives and places the file first in its topic.

---

## Objects (embeds)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files/<file_id>/objects` | List embeds with resolved task_list tasks / info |
| POST | `/files/<file_id>/objects` | Create embed + entity + document object node |
| GET | `/objects/<id>` | Get one embed (expanded) |
| GET | `/objects/graph` | Workspace info map (nodes + related edges, including `diagram_x`/`diagram_y`) |
| PUT | `/objects/graph/positions` | Batch-save map coordinates |
| PATCH | `/objects/<id>` | Update anchor / sort_key / diagram_x / diagram_y |
| DELETE | `/objects/<id>` | Remove object node from body + delete entity |
| GET | `/objects/<id>/links` | List info object links |
| POST | `/objects/<id>/links` | Create link from info object |
| DELETE | `/objects/<id>/links/<link_id>` | Delete link |

**POST body (task_list):** `{ "type": "task_list", "index?" }` — inserts object node at index

**POST body (info):** `{ "type": "info", "title?", "body?", "index?" }`

---

## Task lists

| Method | Path | Description |
|--------|------|-------------|
| GET | `/task-lists/<id>` | Get list + tasks |
| GET | `/task-lists/<id>/tasks` | List tasks (active then done) |
| POST | `/task-lists/<id>/tasks` | Create task `{ "title", "status?", "list_order_index?" }` |
| PUT | `/task-lists/<id>/tasks/order` | `{ "ordered_task_ids": [1,2,3] }` |
| POST | `/tasks/<id>/move` | Cross-list move `{ "target_task_list_id", "insert_index_in_zone", "target_done" }` |

---

## Tasks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks` | List all |
| GET | `/tasks/<id>` | Get |
| PATCH | `/tasks/<id>` | Update title, status, due_date, list_order_index, task_list_id |
| POST | `/tasks/<id>/toggle` | Toggle active/done |
| DELETE | `/tasks/<id>` | Delete task + compact list order |
| GET | `/tasks/<id>/memberships` | View memberships for task |
| PUT | `/tasks/<id>/memberships` | Replace view memberships |

---

## Information pieces

| Method | Path | Description |
|--------|------|-------------|
| GET | `/information/<id>` | Get |
| PATCH | `/information/<id>` | Update title, body, metadata |

---

## Tags

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tags` | List (`?workspace_id=`) |
| POST | `/tags` | Create |
| POST | `/tags/assign` | `{ "tag_id", "entity_type", "entity_id" }` |
| DELETE | `/tags/assign` | Remove assignment (body or query params) |

---

## Views

| Method | Path | Description |
|--------|------|-------------|
| GET | `/views` | List |
| POST | `/views` | Create |
| PATCH | `/views/<id>` | Update |
| DELETE | `/views/<id>` | Delete |
| GET | `/views/<id>/memberships` | Task memberships (`order_index` = section-mode order, `topic_order_index` = topic-mode order) |
| PUT | `/views/<id>/memberships` | Replace ordered memberships |

---

## Agent

| Method | Path | Description |
|--------|------|-------------|
| POST | `/agent/run` | Run tool-using agent |

**POST body:**
```json
{
  "prompt": "Update the daily file…",
  "workspace_id": 1,
  "scope": { "topic_ids": [1], "file_ids": [2] },
  "apply_mode": "direct_apply",
  "context": {}
}
```

`apply_mode` is optional; when omitted the server uses `DEFAULT_MANUAL_APPLY_MODE` from `shared/run_config.py`.

**Response:** `{ "status", "messages", "proposed_changes?", "applied?", "apply_mode?", … }`

---

## Automations

A scope, a trigger, and an ordered series of steps. Saved AI actions are a different resource.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/automations` | List (also backfills section-window rows) |
| GET | `/automations/pending-clears` | Section windows waiting for leftover confirm |
| POST | `/automations` | Create — plus `kind`, `view_id`, `section_key`, `window_duration_minutes` |
| PATCH | `/automations/<id>` | Partial update of those fields |
| DELETE | `/automations/<id>` | Delete (cascades runs and complimentary tasks) |
| POST | `/automations/<id>/run` | Run now on the **stored** scope — same walk the clock would do |
| POST | `/automations/<id>/submit-input` | Store user input and run |
| POST | `/automations/<id>/clear-leftovers` | Approve leftover recycle / archive |
| GET | `/automations/<id>/review-status` | Pending review file ids for complimentary review |
| POST | `/automations/<id>/complete-review` | Mark the review task done if nothing is pending |
| GET | `/automations/<id>/input-topics` | Topics for the input dialog |

`steps` is `[{ "kind": "ai" \| "create_file" \| "unmark_tasks" \| "archive_files", … }]`. An `ai` step is either `{ "action_id" }` or `{ "prompt", "apply_mode" }`.

`schedule` is `daily HH:MM` / `weekly DAY HH:MM` / `monthly PLACEMENT DAY HH:MM` / `monthly N PLACEMENT DAY HH:MM` (every N months), not a cron line.

## Saved AI actions

A prompt on a button. No stored scope — the client sends live `scope` / `hints`, like a typed prompt.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/ai-actions` | List |
| POST | `/ai-actions` | Create — `icon`, `bar_slot`, `requires_user_input`, `user_input_prompt` optional. Topic-scoped rows take extra seats 9–10 (max two per topic) |
| PATCH | `/ai-actions/<id>` | Update; `bar_slot` (1–7 or null) pins/unpins a fixed seat; topic extras use 9–10 |
| PUT | `/ai-actions/bar-order` | `{"ordered_ids": [...]}` → first seven non-topic actions take slots 1..7; topic extras stay |
| DELETE | `/ai-actions/<id>` | Delete |
| POST | `/ai-actions/<id>/run` | Run on optional live `scope` / `hints` |

---

## File versions & diff

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files/<id>/versions` | List snapshots |
| POST | `/files/<id>/diff` | `{ "old_body", "new_body" }` → unified diff hunks |

---

## Uploads

Unchanged: `POST /upload`, static file serving under `/uploads/`.
