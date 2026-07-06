# `core/ai/`

Purpose: AI-specific domain logic that is not presentation code.

What this module covers:
- Resolving AI context from selected topic/file/block/task state.
- Preparing structured AI tool requests.
- Parsing normalized AI outputs for state/application layers.

## Context resolution priority

`AiContextResolver.resolve()` picks text in this order:

1. **Selection** — non-collapsed highlight in a focused text block.
2. **Current line** — collapsed caret on a line (text from line start until `\n`).
3. **Task title** — last task in the topic's tasks file when no text focus applies.

An empty current line does **not** fall back to a previous line or paragraph.

Guidelines:
- Keep this layer UI-independent.
- Keep contracts explicit so behavior is testable and debuggable.
