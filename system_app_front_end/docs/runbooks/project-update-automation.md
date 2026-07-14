# Project Update Automation

End-to-end flow for updating a project from a part-structured log file.

## User workflow

1. On **main**, tap **Log for project…** and pick a project.
2. The app creates a `log` file on main with `anchor_topic_id` set to that project.
3. Right-click in the log → **Add part** uses the anchored project's part list.
4. Write daily notes under each part header.
5. Move the log into the project topic (file menu → **Move to topic…**).
6. If `project_update` is enabled, the backend proposes per-part updates.
7. A companion task appears in the daily view → **Project updates** section.
8. Review each part (plan → execution → tasks), then finalize.
9. Documentation rows are added automatically; a snackbar reports how many.

## Anchored log on main

| Field | Value |
|-------|-------|
| `topic_id` | main topic |
| `anchor_topic_id` | chosen project |
| `type` | `log` |

Part placement resolves parts from `anchor_topic_id` (backend `parts_topic_id_for_file`).

Existing logs can use file menu → **Attach to project…** to set `anchor_topic_id`.

## Automation definition

| Key | `project_update` |
| Trigger | `file_moved` when a `log` file lands in a project |
| Default | disabled |
| Companion | `project_update_review` |
| Proposal types | `project_smart_update`, `project_update_skipped` |

## Change set v2

```json
{
  "version": 2,
  "log_file": { "id": 1, "name": "Log", "date": "2026-07-14" },
  "parts": [
    {
      "part_id": 3,
      "part_name": "Auth",
      "is_new": false,
      "documents": [/* plan, execution, tasks change docs */]
    }
  ],
  "doc_append": { "rows": [{ "date": "2026-07-14", "text": "…" }] }
}
```

Doc rows are **not** shown in the review dialog; they apply on finalize.

## Finalize behavior

Project update edits plan, execution, and tasks **in place** — it does **not** archive or recreate those files (unlike process refresh). Only the matching part blocks are replaced with approved content.

## Backend modules

| Module | Role |
|--------|------|
| `services/ai_smart_update/project_update.py` | Per-part AI orchestration |
| `services/ai_smart_update/log_parser.py` | Parse log part sections |
| `services/ai_smart_update/doc_journey.py` | Narrative doc rows |
| `services/ai_smart_update/finalize_project.py` | In-place finalize |
| `services/automation_actions.py` | `project_update()` action |

## Frontend modules

| Module | Role |
|--------|------|
| `log_for_project_dialog.dart` | Pick project on main |
| `project_update_batch_dialog.dart` | Companion batch review |
| `part_change_review_dialog.dart` | One page per part |
| `AutomationFlowRegistry` | `project_update_review` case |

## Deployment

Run migration `014_project_log_anchor.sql` before enabling the automation on Render.
