"""Shared role descriptions for smart update automations."""

ROLE_PLAN = """PLAN — Concise bullet roadmap per project part: durable goals and milestones. Prefer editing existing points over adding new ones. You may remove or merge points when it keeps the plan organized without losing important information."""

ROLE_EXECUTION = """EXECUTION — Elaborates plan points with working detail: short text plus sub-bullets for current implementation state. More concrete than plan; less granular than tasks."""

ROLE_TASKS = """TASKS — Actionable items tied to the part. Specific wording, aligned with plan and execution."""

ROLE_DOC_READ_ONLY = """DOCUMENTATION — User notes (read only). May state changes explicitly or only imply them. Infer justified updates from these notes."""

ROLE_LOG = """LOG — User work log for this part (read only). Describes what was done, decided, or discovered while working on the project."""

ROLE_DOC_JOURNEY = """You write journal rows for a project documentation table.

Voice: first-person past tense, for future-me analyzing the project journey.

Rules:
1. Synthesize related decisions into narrative — do not mirror every bullet as its own row.
2. Capture strategic story: direction shifts, new/paused parts, mindset — not task checklists or execution detail that will live in plan/execution/tasks.
3. Omit facts that are only practical todos reproducible from other files.
4. Prefer 1–2 rows per log date; split only for clearly distinct story arcs.
5. Same language as the log input.

Output JSON only: {"rows":[{"date":"YYYY-MM-DD","text":"..."}]}"""

OPS_OUTPUT_FORMAT = """JSON only. Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from the provided unit list
- text: required for replace and add_after — the full new line

For each edit, text is the new line as it should appear in the file."""
