# Development guide

**The coding agent reads this before every change.** It holds only what applies to every task; situational rules live in [`NOTES.md`](NOTES.md).

Not for the production agent — that one reads its instructions from the database (`agent_configs.system_prompt`).

---

## How we work

A test cycle is slow (deploy, restart, click through the app), so a wrong guess is expensive. Gather only what is relevant, then move in small, decisive steps.

1. **Read before changing** — the relevant `AREA.md`, and the [`NOTES.md`](NOTES.md) section that matches what you are touching. Not the whole tree.
2. **Ask when it is ambiguous** — if the request has two reasonable readings, ask one or two sharp questions instead of guessing.
3. **One change at a time** — the smallest set of files that does the job. Avoid large unrelated change sets.
4. **Push to `main` after backend changes** so Render redeploys and the Flutter app can be tested against the live API. Frontend-only changes need no deploy.
5. **Update the area's `AREA.md` in the same commit** — both sides if the change spans front and back.
6. **Say what changed and why, briefly** — discuss the solution, but a few sentences, not an essay. Lead with the outcome, keep the reasoning that affects a decision, and drop the rest.

When the user says “remember this”, add it to [`NOTES.md`](NOTES.md) under the matching section, with a date.

---

## Current state

We are building a **new version** of system_app on `main`. Much of the codebase is mid-rewrite and still needs work — treat incomplete areas as expected, not finished. (“v3” means this rewrite, not the legacy document JSON format; file bodies are **v4 marker text**.)

Known unresolved issues live in [`BACKLOG.md`](BACKLOG.md), grouped by area. We clear one area at a time.

**v1 reference:** behavior removed in the rewrite still exists on `origin/legacy/v1` ([GitHub](https://github.com/tsoofLahav/system_app_v3/tree/legacy/v1)). Use it when porting or recovering something lost:

```bash
git fetch origin && git checkout legacy/v1   # look
git checkout main                            # back to current work
```

---

## System areas

The code is physically split by area. Each area owns its folder and an `AREA.md` with its rules and logic. Matching areas exist on both sides where relevant, and their docs mirror each other. **UI is what it looks like; UX is what happens and where things live.**

| Area | Backend | Frontend |
|------|---------|----------|
| **File structure & functionality** | [`areas/files/AREA.md`](system_app_back_end/areas/files/AREA.md) | [`areas/files/AREA.md`](system_app_front_end/lib/areas/files/AREA.md) |
| **Production agent** | [`areas/production_agent/AREA.md`](system_app_back_end/areas/production_agent/AREA.md) | [`areas/production_agent/AREA.md`](system_app_front_end/lib/areas/production_agent/AREA.md) |
| **Automations** | [`areas/automations/AREA.md`](system_app_back_end/areas/automations/AREA.md) | [`areas/automations/AREA.md`](system_app_front_end/lib/areas/automations/AREA.md) |
| **Objects** (incl. **tasks**) | [`areas/objects/AREA.md`](system_app_back_end/areas/objects/AREA.md) | [`areas/objects/AREA.md`](system_app_front_end/lib/areas/objects/AREA.md) |
| **UI** — visual style only | — | [`areas/ui/AREA.md`](system_app_front_end/lib/areas/ui/AREA.md) |
| **UX** — flow and experience | — | [`areas/ux/AREA.md`](system_app_front_end/lib/areas/ux/AREA.md) |

Area maps: [backend](system_app_back_end/areas/README.md) · [frontend](system_app_front_end/lib/areas/README.md)

### Where the production agent's own prompt lives

| Layer | Location |
|-------|----------|
| Git source (edit here) | [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) |
| Runtime | `agent_configs.system_prompt` in PostgreSQL |
| Sync (local) | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |
| Sync (Render) | Automatic on web boot (`RENDER=true`) via internal DB URL |

---

## All documentation

### Root

| Doc | Purpose |
|-----|---------|
| [`NOTES.md`](NOTES.md) | Situational rules: editor keyboard safety, text model, objects, layout, agent, history |
| [`CARET_AND_WRITING_FOCUS.md`](CARET_AND_WRITING_FOCUS.md) | Gathered caret, focus, and IME rules (body vs object, remount safety) |
| [`AGENTS.md`](AGENTS.md) | Monorepo entry and task routing |
| [`BACKLOG.md`](BACKLOG.md) | Known unresolved issues, grouped by area |
| [`CONSTITUTION.md`](CONSTITUTION.md) | Product purpose and principles — read-only, never edit |
| [`LEGACY.md`](LEGACY.md) | How to browse and compare the pre-rewrite `legacy/v1` branch |
| [`README.md`](README.md) | Repo layout for a human arriving fresh |

### Per project

| Doc | Purpose |
|-----|---------|
| [`system_app_back_end/AGENTS.md`](system_app_back_end/AGENTS.md) | Flask layout, deploy loop, backend workflow |
| [`system_app_back_end/docs/API.md`](system_app_back_end/docs/API.md) | REST endpoint reference |
| [`system_app_back_end/areas/README.md`](system_app_back_end/areas/README.md) | Backend area map and rules |
| [`system_app_front_end/AGENTS.md`](system_app_front_end/AGENTS.md) | Frontend workflow and guardrails |
| [`system_app_front_end/README.md`](system_app_front_end/README.md) | Flutter client setup and run |
| [`system_app_front_end/lib/README.md`](system_app_front_end/lib/README.md) | `lib/` folder overview |
| [`system_app_front_end/lib/areas/README.md`](system_app_front_end/lib/areas/README.md) | Frontend area map and rules |

### Deep dives (frontend)

| Doc | Purpose |
|-----|---------|
| [`DOCUMENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/DOCUMENT_TEXT.md) | v4 marker text as the file source of truth |
| [`FLUENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/FLUENT_TEXT.md) | One continuous text with embedded objects — caret, move, delete |
| [`RICH_TEXT.md`](system_app_front_end/lib/areas/files/rich_text/RICH_TEXT.md) | Inline formatting (bold, italic, underline, size) |
| [`RTL.md`](system_app_front_end/lib/areas/files/rich_text/rtl/RTL.md) | Caret and direction policy for Hebrew text |
| [`BILINGUAL.md`](system_app_front_end/lib/core/l10n/BILINGUAL.md) | Building UI that works in both English and Hebrew |
| [`l10n/README.md`](system_app_front_end/lib/core/l10n/README.md) | Where user-facing strings live |

### Content and tooling

| Doc | Purpose |
|-----|---------|
| [`content/README.md`](content/README.md) | DB-bound content — edited in git, synced into PostgreSQL |
| [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) | The production agent's standing instructions |
| [`content/production_agent/reference.md`](content/production_agent/reference.md) | Tool descriptions and examples for the production agent |
| [`docs/canvases/README.md`](docs/canvases/README.md) | Versioned snapshots of the Cursor canvases |
