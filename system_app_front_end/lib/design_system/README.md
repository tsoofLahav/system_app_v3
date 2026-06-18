# `design_system/`

Purpose: shared visual language and reusable presentation primitives.

## Visual Contract

The app is a personal operating system, so the interface should reduce mental load rather than ask for attention. The style is mature, calm, modern, practical, and color-supported.

Surface hierarchy:
- Canvas: quiet environmental background with a soft topic tint.
- Files: primary working surfaces and the strongest visual objects on the page.
- Floating controls: compact glass controls that stay available without competing with files.
- Dialogs: Apple-style soft glass panels with one shared structure, small type, gentle separators, padding, title treatment, and action row.
- Sidebar: Apple-style soft glass navigation; it supports context switching but does not dominate the workspace.
- Topic header: plain text over a gentle top gradient veil, with no framed title capsule.

Color rules:
- Topic color is atmospheric: use it as a subtle canvas or glass tint, not as a loud card color.
- Text stays soft charcoal; secondary text is muted.
- Borders and shadows are restrained so the app feels composed rather than toy-like.

Spacing rules:
- Files receive the largest share of the viewport.
- Floating headers use minimal vertical clearance because they are overlay chrome.
- Internal file gaps stay compact and readable.
- Additional files appear lower in the scroll flow so the first view stays focused.

Typography rules:
- English uses Inter for a calm, neutral interface voice.
- Hebrew uses SF Hebrew on Apple platforms, with system Hebrew fallbacks where SF Hebrew is unavailable.

What lives here:
- Tokens: colors, typography, spacing, icon references.
- Shared visual components: glass surfaces, note containers, layout icons.
- Theme wiring used by the whole app.

Ownership boundaries:
- Visual consistency and primitive styling belong here.
- Domain semantics (topic/task/file business rules) do not.

Adoption rules:
- Prefer token reuse over new ad-hoc colors/sizes.
- If a visual pattern repeats in two features, promote it here.

Guidelines:
- Change tokens/components here before adding local style overrides.
- Keep styles composable and predictable across features.
- Avoid feature-specific business semantics in design-system files.
