# Legacy v1 reference

The full **pre-rewrite** codebase (blocks, file types, registries, old automations/AI) is preserved on branch:

**[`legacy/v1`](https://github.com/tsoofLahav/system_app_v3/tree/legacy/v1)** — frozen at commit `488ed25`

`main` is the v2 document-model rewrite (`355bb65` and later).

## Browse or compare

```bash
# View old files without switching main
git show legacy/v1:system_app_front_end/lib/core/app_state.dart

# Diff one file vs current main
git diff legacy/v1..main -- system_app_front_end/lib/features/blocks/

# Open old tree in another folder
git worktree add ../system_app-v1-reference legacy/v1
```

## What v1 had (for fix reference)

- Block/file-type architecture (`features/blocks/`, registries)
- Hardcoded views and automation definitions
- Unit-based diff / `change_review_dialog`
- Migrations `002`–`017` (not v2 `001_v2_schema.sql`)

Do not merge `legacy/v1` into `main` wholesale — use it as read-only reference while fixing v2.
