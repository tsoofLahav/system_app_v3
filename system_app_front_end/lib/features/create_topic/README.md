# `features/create_topic/`

Purpose: create/edit topic flows.

What this module covers:
- Topic creation and edit dialogs.
- Input validation and user-facing form guidance.
- Selection of topic type and the initial files to create.

File choices:
- Project topics start with `overview`, `tasks`, and `execution` as main files,
  with `doc` and `plan` available as additional project files.
- Process topics start with `overview`, `plan`, `tasks`, and `doc`.
- Area topics start with `tasks` and `doc`.
- Others topics start with `text` and `doc` (minimal structure).
- The add-file dialog offers every file type for every topic type.
- File names, order, and main/additional placement come from `core/registry/file_registry.dart` (main topic uses `allFileTypes`; main section capped at 3 files).
- Initial blocks for each selected file come from `core/registry/file_behavior_registry.dart`.

Project structure:
- Project work is split into ordered **parts** — see [`../features/blocks/PARTS.md`](../features/blocks/PARTS.md).
- `overview` is a generated status surface, not the source of the part structure.

Guidelines:
- Use `core/registry` for file catalogs, defaults, and behavior profiles.
- Keep business rules out of widget literals when possible.
