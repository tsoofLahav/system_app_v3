# `features/create_topic/`

Purpose: create/edit topic flows.

What this module covers:
- Topic creation and edit dialogs
- Topic type selection and initial file checkboxes
- Add-file dialog (any file type, any topic)

File choices (defaults from [`core/registry/file_registry.dart`](../../core/registry/file_registry.dart)):

| Topic type | Essence at creation | Additionals at creation |
|---|---|---|
| Project | `overview`, `tasks`, `execution` | `doc`, `plan`, `data` |
| Process | `overview`, `plan`, `tasks` | `doc`, `data` |
| Area | `tasks`, `data`, `text` | `doc` |
| Others | none (empty topic) | none |

- The add-file dialog offers every file type not already in the topic.
- Default file names use the translated type label (`fileTypeLabel`), not custom English names.
- Essence pane holds at most 3 files (`maxMainFilesPerTopic`).
- Initial blocks per file come from [`file_behavior_registry.dart`](../../core/registry/file_behavior_registry.dart).

Project structure:
- Project work uses **parts** — see [`../blocks/PARTS.md`](../blocks/PARTS.md).
- `overview` is a generated status surface, not the source of part structure.

Guidelines:
- Use `core/registry` for catalogs and profiles; keep business rules out of widget literals.
