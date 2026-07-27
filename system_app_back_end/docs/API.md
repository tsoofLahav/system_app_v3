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
| POST | `/topics` | Create |
| PATCH | `/topics/<id>` | Update |
| DELETE | `/topics/<id>` | Delete cascade |

**POST body:** `{ "workspace_id", "name", "icon?", "color?", "order_index?" }`

**PATCH:** `name`, `icon`, `color`, `order_index`, `archived_at`

---

## Files

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files` | List all |
| GET | `/files/<id>` | Get one (includes `body`) |
| GET | `/topics/<topic_id>/files` | Files for topic |
| POST | `/files` | Create |
| PATCH | `/files/<id>` | Update (name, body, is_essence, order_index, meta, archived_at) |
| DELETE | `/files/<id>` | Delete cascade |

**POST body:** `{ "topic_id", "name", "body?", "is_essence?", "order_index?", "meta?" }`

---

## Objects (embeds)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files/<file_id>/objects` | List embeds with resolved task_list tasks / info |
| POST | `/files/<file_id>/objects` | Create embed + entity + document object node |
| GET | `/objects/<id>` | Get one embed (expanded) |
| PATCH | `/objects/<id>` | Update anchor / sort_key |
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
| GET | `/views/<id>/memberships` | Task memberships |
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
  "apply_mode": "review",
  "context": {}
}
```

**Response:** `{ "run_id", "status", "messages", "proposed_changes?", "applied?" }`

---

## Automations

| Method | Path | Description |
|--------|------|-------------|
| GET | `/automations` | List |
| POST | `/automations` | Create |
| PATCH | `/automations/<id>` | Update |
| DELETE | `/automations/<id>` | Delete |
| POST | `/automations/<id>/run` | Manual run → same as agent |

---

## File versions & diff

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files/<id>/versions` | List snapshots |
| POST | `/files/<id>/diff` | `{ "old_body", "new_body" }` → unified diff hunks |

---

## Uploads

Unchanged: `POST /upload`, static file serving under `/uploads/`.
