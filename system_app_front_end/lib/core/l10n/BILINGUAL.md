# Bilingual UI (English / Hebrew)

Rules for building UI that works in both LTR (English) and RTL (Hebrew).
Follow this whenever you add labels, rows with controls, or dialogs.

## Data vs display

| Layer | Language | Example |
|-------|----------|---------|
| Database / API | English keys only | `process_refresh`, `weekly`, `Daily` |
| On-screen UI | Translated via `AppStrings` | `עדכון כל התהליכים` |

- User-written content (topic names, task titles, notes) stays as typed — never auto-translated.
- Built-in catalog items (view types, file names, automation definitions) map English keys → localized labels in [`app_strings.dart`](app_strings.dart).

### Adding a new built-in catalog item

1. Keep the English identifier in backend/data.
2. Add entries to **both** language maps in `app_strings.dart` (same keys).
3. Expose a helper on `AppStrings` (e.g. `automationNameLabel(key)`).
4. Use the helper in UI — never render `definition.name` directly if it comes from the API in English.

## Text direction

- App-wide direction is set once in [`app.dart`](../app.dart) from `AppState.textDirection`.
- Do **not** wrap whole screens/dialogs in extra `Directionality` unless opening a subtree outside `MaterialApp` (rare).
- Do **not** force `TextDirection.ltr` on rows to “fix” Hebrew — it mirrors English physical layout and breaks RTL expectations.

## Layout rules

### Prefer directional “start / end” over left / right

| Use | Avoid |
|-----|-------|
| `TextAlign.start` | `TextAlign.left` / `TextAlign.right` |
| `CrossAxisAlignment.start` | `CrossAxisAlignment.left` |
| `AlignmentDirectional.centerStart` | `Alignment.centerLeft` |
| `EdgeInsetsDirectional.only(start: …)` | `EdgeInsets.only(left: …)` |
| `BorderDirectional` | `Border(left: …)` when side matters |

### Rows with a trailing control (toggle, chevron, button)

Use [`StartTrailingRow`](../design_system/bilingual_layout.dart):

```dart
StartTrailingRow(
  content: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [ /* title, subtitle, actions under title */ ],
  ),
  trailing: AppSwitch(...),
)
```

**Behavior**

- **English (LTR):** content left, control right.
- **Hebrew (RTL):** content right, control left.

This matches platform settings lists. Never wrap this row in `Directionality(textDirection: TextDirection.ltr)`.

### Dialog action buttons

Use [`DialogActionsRow`](../design_system/bilingual_layout.dart) inside `AppGlassDialog` — actions align to the reading-direction **trailing** edge (right in English, left in Hebrew).

### When physical placement is required (rare)

If a control must stay on a specific **physical** side regardless of language (e.g. a canvas tool), document why in code and use explicit `Alignment.centerLeft` / `Alignment.centerRight`. Default to directional layout unless there is a strong reason.

## Strings checklist

Before merging UI work:

- [ ] No new user-facing English literals in feature widgets — add keys to `_uiEn` / `_uiHe`.
- [ ] English API keys displayed to users go through an `AppStrings` map helper.
- [ ] Hebrew map has the same keys as English.
- [ ] Rows with switches/icons use `StartTrailingRow` or equivalent directional layout.
- [ ] Text fields and labels use `TextAlign.start`.
- [ ] Test the screen in **both** languages from Preferences.

## Automation definitions (example)

Backend returns English `name` / `description`. UI must call:

```dart
final s = state.strings;
final name = s.automationNameLabel(rule.key, fallback: definition?.name);
final description = s.automationDescriptionLabel(
  rule.key,
  fallback: definition?.description,
);
```

Keys live in `_automationNamesEn` / `_automationNamesHe` and `_automationDescriptionsEn` / `_automationDescriptionsHe`.

## Related

- String maps: [`app_strings.dart`](app_strings.dart)
- Layout helpers: [`bilingual_layout.dart`](../design_system/bilingual_layout.dart)
- Design system overview: [`design_system/README.md`](../design_system/README.md)
