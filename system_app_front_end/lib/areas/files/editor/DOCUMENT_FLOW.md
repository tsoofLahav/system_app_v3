# Document flow (save / poll / remote apply)

How an open file’s body moves between Super Editor, draft cache, PATCH, and poll — and how blanks (`[SPACER]`) stay honest. Spec for the marker dialect: [`DOCUMENT_TEXT.md`](DOCUMENT_TEXT.md). Conflict decisions: [`edit_conflict.dart`](edit_conflict.dart).

## Stages (ordered)

| Stage | SoT | What happens |
|-------|-----|----------------|
| **Type** | SE `MutableDocument` | User edits. Empty paragraphs are real nodes. |
| **Draft** | `filesById` + `putOpenDocumentDraft` | Each change serializes via the bridge (`mutableDocumentToMarkerText`) and mirrors the draft so remount/refresh cannot drop unsaved blanks. |
| **PATCH** | Server `document_json` + `content_revision` | Debounced (~450ms) with `base_revision`. Success: `_lastSavedJson` / local tip revision advance; `dirty=false`. 409 → keep local text, 3-way / lookalike. |
| **Poll** | `inboundDocumentJson` + `inboundContentRevision` | ~5s section poll stores the **server tip** here — not over a dirty draft in `filesById`. |
| **Decide** | `decideRemoteEdit` | Clean → take remote. Dirty + different inbound → 3-way / ask. Same as baseline → ignore. |
| **Reload** | SE remount via `runWhenKeyboardIdle` | Only after takeRemote / merge apply. Bridge expands `[SPACER n="N"]` → N empties. |
| **Agent apply** | BE marker text | Bare `\n\n\n` gaps become spacers; consecutive empties stay separate `n="1"` (no merge into `n="2"`). |

Blanks on disk are `[SPACER]` / `[SPACER n="N"]`. Never treat a typed empty paragraph as “nothing.”

## Stale-poll rule

After a successful PATCH, a late list/GET can still return the **pre-save** body (lower `content_revision`). Taking it remounts the older text and drops blanks that just saved.

Skip remote apply when either:

1. **`inboundRev < localRev`** — `shouldIgnorePolledBody` (`edit_conflict.dart`): polled revision behind `_currentFile.contentRevision`.
2. **`_documentPatchInFlight`** — PATCH still running (success or 409 path); do not apply poll mid-flush.

Fresh polls (`inboundRev > localRev`) still go through `decideRemoteEdit`.

## Dirty draft + inbound stash

While dirty, poll must **not** overwrite the live draft in `filesById`. Server tip lives in `inboundDocumentJson`; SE reads remote from that stash for decide / 3-way. Topic refresh uses `mergeTopicFileForRefresh` keep-local when dirty. This split is intentional SoT, not a band-aid.

## Spacer audit (dormant)

[`spacer_audit.dart`](spacer_audit.dart) is kept but **not wired**. To re-enable blank-line forensics:

1. Import `spacer_audit.dart` in `super_document_editor.dart` and `app_state.dart`.
2. Wire tags at these call sites:
   - `serialize` / `serialize.doc` — after `mutableDocumentToMarkerText` on document change
   - `beforePatch` — body about to PATCH in `_flushPendingChanges`
   - `afterPatch` — updated `document_json` in `updateFile` success path
   - `poll.inbound` — when poll writes `inboundDocumentJson`
   - `reload.in` / `reload.loaded` — `_reloadFromStored` input body and loaded `MutableDocument`
3. Search the console for `spacerAudit`. The first tag where `spacers=` drops is the stage that lost blanks.
