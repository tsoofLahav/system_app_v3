# `core/services/`

Purpose: API access and external I/O boundaries.

What this layer does:
- Encapsulates REST endpoints by domain (`TopicService`, `FileService`, `TaskService`, etc.).
- Maps request payloads and parses response models.
- Centralizes transport error surfaces for upstream handling.

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
