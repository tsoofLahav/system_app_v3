# `core/services/`

Purpose: API access and external I/O boundaries.

What this layer does:
- Encapsulates REST endpoints by domain (`TopicService`, `FileService`, `TaskService`, etc.).
- Maps request payloads and parses response models.
- Centralizes transport error surfaces for upstream handling.

| File | Role |
|---|---|
| `api_service.dart` | Shared HTTP transport and base URL |
| `bootstrap_service.dart` | Initial app data load |
| `topic_service.dart` | Topics CRUD |
| `file_service.dart` | Files CRUD |
| `block_service.dart` | Blocks CRUD |
| `task_service.dart` | Tasks CRUD |
| `task_view_service.dart` | Task views and sections |
| `image_service.dart` | Image upload and URL resolution |
| `ai_service.dart` | AI tool execution requests |
| `ai_proposal_service.dart` | AI proposal create/approve/reject |
| `automation_service.dart` | Automation rules and runs |
| `automation_definition_service.dart` | Built-in automation definitions |
| `automation_companion_service.dart` | Automation companion flows |
| `part_service.dart` | Project parts list and file placement |
| `process_documentation_input_service.dart` | Process documentation inputs |
| `task_reset_acknowledgement_service.dart` | Task reset acknowledgements |

Ownership map:
- Topics/files/blocks/tasks/task views: CRUD and filtered list endpoints.
- Images: upload and path response handling.
- AI: tool execution requests and structured responses.

Error model:
- Services should surface API failures clearly to `AppState`.
- User-facing phrasing belongs in feature/UI layer, not services.

Rules:
- Keep services stateless and side-effect-limited to network calls.
- No widget or presentation logic in services.
- Return typed model objects consumed by `AppState`.
