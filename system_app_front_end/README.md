# system_app_front_end

Flutter client for `system_app` (macOS desktop + iOS).

## Before working

1. [`../DEVELOPMENT.md`](../DEVELOPMENT.md) — v3 status, deploy loop, area map
2. [`AGENTS.md`](AGENTS.md) — frontend workflow and guardrails
3. The relevant [`lib/areas/<area>/AREA.md`](lib/areas/README.md) — rules for the area you are touching
4. [`../CONSTITUTION.md`](../CONSTITUTION.md) — product direction, before large changes

## Documentation index

| Doc | Purpose |
|-----|---------|
| [`lib/areas/README.md`](lib/areas/README.md) | Area map and the UI/UX split |
| [`lib/README.md`](lib/README.md) | Folder layout and placement rules |
| [`lib/areas/files/rich_text/RICH_TEXT.md`](lib/areas/files/rich_text/RICH_TEXT.md) | Span invariants |
| [`lib/core/l10n/BILINGUAL.md`](lib/core/l10n/BILINGUAL.md) | English/Hebrew and RTL |
| [`../system_app_back_end/docs/API.md`](../system_app_back_end/docs/API.md) | REST endpoints |

Each area's `AREA.md` is the source of truth for that area's behavior.

## Run

```bash
flutter pub get
flutter run -d macos
```

### iOS (phone shell)

On native iOS the app uses a separate shell: drawer sidebar, one-file-at-a-time `PageView` (every file in the topic, no layouts), a one-row bottom bar that scrolls sideways, a name-list bring-file sheet, and a phone-sized pending-review dialog. Desktop behavior is unchanged.

```bash
flutter run -d ios
```

Smoke check on simulator or device:

- Open the drawer, switch topics and task views
- Edit a file — type, add a list, add a table
- Add a file / create a topic
- Bring a file from another topic
- Open preferences and automations from the bottom bar
