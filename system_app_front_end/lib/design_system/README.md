# `design_system/`

Purpose: shared visual language and reusable presentation primitives.

## Visual Contract

The app is a personal operating system, so the interface should reduce mental load rather than ask for attention. The style is mature, calm, modern, practical, and color-supported.

Surface hierarchy:
- Canvas: quiet environmental background with a soft topic tint.
- Files: primary working surfaces (`NoteCard`) — strongest objects on the page; not dialog glass.
- Floating chrome: `+`, bottom bar segments, reorder tiles, dividers — shared `AppGlassStyle` presets.
- Dialogs: soft glass panels via `AppGlassStyle.dialog`.
- Sidebar: soft glass navigation; supports context switching without dominating the workspace.
- Topic header: plain text over a gentle top gradient veil; minimal vertical clearance.

## Glass presets (`AppGlassStyle`)

All floating chrome must use a preset from [`glass_surface.dart`](glass_surface.dart). Do not invent one-off blur/tint values.

| Preset | Use |
|--------|-----|
| `dialog` | Modals, `AppGlassDialog` |
| `floating` | `+` button, bar tool segments, reorder tiles, toggle capsule |
| `aiAccent` | Bottom-bar AI segment — cyan tint, stronger border, optional label |

## Spacing & density

Cross-app tokens in `AppSpacing`, `AppLayoutSpacing`, `AppTopicHeaderMetrics`:

- Canvas padding: **12px**; file layout gap: **8px**; note inner padding: **12px**.
- Topic scroll top inset: **~38px** (header + float margin, not oversized).
- Block gap inside files: **3–4px**; list/task line height: **~1.38**.
- Task row vertical padding: **0–1px**; custom `TaskMark` (~14px), not Material checkbox.

Files receive the largest share of the viewport. Additional files sit lower in the scroll flow.

## More-files divider

`FilesSectionDivider`: outline-only circle (canvas-transparent fill), `…` when collapsed and `−` when expanded at the **same 14px** visual weight. Subtle lines on both sides.

## Bottom bar

Three glass segments on topic view (not one monolithic pill):

1. **Tools** — preferences, automations, layout (`floating`).
2. **Toggle** — pane drag mode (`floating` interior).
3. **AI** — always visible on topic view (`aiAccent`); all tool icons shown; **no expand/collapse AI button**; tools dim/disabled when there is no AI context. Small **AI** label on the segment outline.

## Color & typography

- Topic color is atmospheric — subtle canvas or glass tint, not loud card color.
- Text: soft charcoal; secondary text muted.
- English: Inter; Hebrew: SF Hebrew with system fallbacks.
- Prefer `listItemStyle` / `taskRowStyle` for dense list and task content.

## Ownership

- Tokens and visual primitives live here.
- Domain semantics (topic/task/file rules) do not.

## Adoption

- Change tokens/components here before local style overrides.
- If a pattern repeats in two features, promote it here.
