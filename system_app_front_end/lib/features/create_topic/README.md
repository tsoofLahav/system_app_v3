# `features/create_topic/`

Purpose: create/edit topic flows.

What this module covers:
- Topic creation and edit dialogs.
- Input validation and user-facing form guidance.
- Selection of topic type and the initial files to create.

File choices:
- Project topics start with `overview`, `text`, and `tasks`.
- Process topics start with `overview`, `plan`, `tasks`, and `doc`.
- Area topics start with `tasks` and `doc`.
- The add-file dialog offers every file type for every topic type.
- File names, order, and main/additional placement come from `core/registry/file_registry.dart`.
- Initial blocks for each selected file come from `core/registry/file_behavior_registry.dart`.

Guidelines:
- Use `core/registry` for file catalogs, defaults, and behavior profiles.
- Keep business rules out of widget literals when possible.
