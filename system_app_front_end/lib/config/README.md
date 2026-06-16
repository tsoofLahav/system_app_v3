# `config/`

Purpose: centralize runtime configuration values used by services and app startup.

What belongs here:
- API base URL and runtime environment constants.
- Compile-time flags read from `--dart-define`.

Guidelines:
- Keep this layer minimal and environment-focused.
- Do not place feature or business logic here.
- If config changes behavior, update related docs in `core/` or `features/`.
