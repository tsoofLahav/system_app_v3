# `core/ai/`

Purpose: AI-specific domain logic that is not presentation code.

What this module covers:
- Resolving AI context from selected topic/file/block/task state.
- Preparing structured AI tool requests.
- Parsing normalized AI outputs for state/application layers.

Guidelines:
- Keep this layer UI-independent.
- Keep contracts explicit so behavior is testable and debuggable.
