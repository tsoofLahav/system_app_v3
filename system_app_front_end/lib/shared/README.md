# `shared/`

Purpose: reusable UI building blocks shared by multiple features.

What belongs here:
- Cross-feature widgets and UI helpers.
- Small reusable interaction primitives.

Promotion rule:
- A widget belongs in `shared/` only when it is used by multiple features
  or represents a stable cross-feature pattern.

Guidelines:
- Keep shared components feature-agnostic.
- Promote duplicated feature widgets here only after reuse is clear.
