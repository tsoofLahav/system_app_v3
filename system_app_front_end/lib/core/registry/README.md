# `core/registry/`

Purpose: declarative product rules and defaults (the decision layer).

What lives here:
- File catalog per topic type ([`file_registry.dart`](file_registry.dart))
- File behavior profiles ([`file_behavior_registry.dart`](file_behavior_registry.dart))
- Block type catalog ([`block_registry.dart`](block_registry.dart))
- Topic appearance defaults, view definitions, automation flow metadata

Decision precedence:
1. Explicit backend state (`is_main`, `order_index`, stored settings)
2. Registry defaults/fallbacks
3. UI-level display choices

## Glossary

| Term | Meaning |
|---|---|
| **Essence (primary pane)** | Up to 3 files shown in the main topic canvas (`is_main: true`). UI label: Essence / עיקר. Code still uses `isMain`, `mainFiles`. |
| **Additionals (more files)** | Secondary files below the divider (`is_main: false`). |
| **Main topic (home)** | The special home topic (`topic.isMain`, name `main`). Sidebar label unchanged. |
| **Daily file** | The automation anchor file on the main topic (`file.type == 'main'`). Behavior matches `text`; default name comes from `fileTypeLabel('main')` → Daily / יומי. |

New files default to the **translated file type label** (`AppStrings.fileTypeLabel`), not custom English names like “Summary” or “Recap”.

## All file types

Any type can be added to any topic via the add-file dialog. Topic type only controls **creation defaults**.

| Type key | Purpose |
|---|---|
| `main` | Daily file on the home topic (automation anchor) |
| `text` | Free writing — most versatile insert menu |
| `overview` | Generated recap / status surface |
| `plan` | Planning steps |
| `tasks` | Dedicated task entry (`task_list`) |
| `doc` | Documentation tables |
| `board` | Image canvas |
| `execution` | Execution steps (header + list) |
| `log` | Project log on the home topic |
| `data` | Reference / details storage |

Essence capacity: `FileRegistry.maxMainFilesPerTopic` (3). Promote/reorder evicts the last essence file when full.

## Topic creation defaults

| Topic type | Essence | Additionals |
|---|---|---|
| **Project** | `overview`, `tasks`, `execution` | `doc`, `plan`, `data` |
| **Process** | `overview`, `plan`, `tasks` | `doc`, `data` |
| **Area** | `tasks`, `data`, `text` | `doc` |
| **Others** | none | none |
| **Main topic (bootstrap)** | Daily (`main`) only | user-added files |

## File behavior model

File type controls creation UX, not rendering capability. Any file may contain any block type; profiles only set **default blocks**, **Add block suggestions**, and **gap-click insert**.

The editable file title is the primary header. Profiles do not seed an extra top `header` block by default.

### Behavior profiles

| Profile / file type | Default blocks | Gap insert | Add block suggestions |
|---|---|---|---|
| `text`, `main` (Daily) | `text` | `text` | all insertable blocks (see below) |
| `data` | `text` | `text` | `header`, `text`, `details`, `table`, `list` |
| `overview` | `summary`, `task_list`, `table`, `text` | `text` | `header`, `text`, `summary`, `task_list`, `table`, `list` |
| `plan` | `text`, `list`, `text` | `text` | `header`, `text`, `summary`, `list`, `image` |
| `tasks` | `task_list` | none | `header`, `task_list` |
| `doc` | `table`, `text` | `text` | `header`, `text`, `summary`, `graph` |
| `board` | `board` | none | none (canvas menu) |
| `execution` | `header`, `list`, `text` | `text` | `text`, `header`, `summary`, `list`, `graph`, `image` |
| `log` | `text` | `text` | `header`, `text`, `summary`, `list` |

### Block insert rules

- **Insertable block types** (`BlockRegistry.insertableBlockTypes`): `header`, `text`, `summary`, `list`, `task_list`, `image`, `table`, `graph`, `details`
- **`details` menu item** appears only in `text` and `data` files (not auto-appended elsewhere)
- **`text` / Daily** offer every insertable block type
- Renderer accepts all known block types regardless of file type

Task files edit entirely inside `task_list`. Board files use one `board` block and a canvas UI.

## Project parts

Projects use a first-class **`parts` entity** (see [`../../features/blocks/PARTS.md`](../../features/blocks/PARTS.md)).

- Part placement supported in `plan`, `execution`, `tasks`, `log`
- `overview` is generated only

How to use it:
- Change rules here first, then adapt UI in features
- Keep these files data-first (constants/maps), not widget logic
