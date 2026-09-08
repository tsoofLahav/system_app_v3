# Document sync and text flow

## Ownership

`DocumentSync` is the per-file coordinator, owned by AppState for the session rather than by a disposable widget. Its baseline is an inseparable server body/revision pair. Its draft and generation represent local edits. There is at most one running synchronization per file; concurrent triggers await that same operation.

The mounted Super Editor owns caret, IME, and runtime document nodes. It mirrors changes to the coordinator and draft cache immediately. Object text stays in object payloads and task rows, never in the marker document body.

## Triggers

- Typing: 450ms debounce requests synchronization.
- Open app: the existing 5s tick requests synchronization of mounted editors, including clean editors; it also refreshes placement and object payloads.
- Opening a file requests an immediate sync.
- Topic/view/archive navigation flushes mounted editors before leaving.
- AI actions and manual automation runs flush mounted object text and document drafts, then await outstanding object writes before sending the request.
- Agent results refresh touched files; the editor routes a newer revision through its coordinator.

These are triggers, not competing body-application paths. Closed-app execution/notifications are outside this protocol.

## One operation

1. Fetch the server body/revision. Ignore revisions older than the acknowledged baseline.
2. Compare baseline, local draft, and server. Identical/one-sided cases preserve the original bytes. Different nonoverlapping changes merge; overlaps require lookalike review.
3. If the draft changed during the read/review, recompute before writing.
4. PATCH the captured result with the fetched revision. A 409 returns to fetch/merge, never a blind retry with a newer token.
5. Carry edits made during PATCH onto the acknowledged result using the captured local draft as the rebase base. Do not clear newer edits.
6. Wait for keyboard idle, recheck the generation, publish the paired baseline and draft, and apply only to this editor if its displayed snapshot actually changed. Continue if newer edits remain dirty.

A failed request retains the draft and baseline for retry. Navigation/AI await failures rather than treating them as successful saves. If review is required after the widget has disappeared, the session retains the draft; it needs a mounted editor to ask.

The renderer remembers the exact snapshot it displayed. Do not compare a freshly serialized document with raw inbound text on every poll: equivalent marker representations could otherwise cause repeated remounts.

## Server concurrency

`File.content_revision` is the SQLAlchemy mapper version column. ORM UPDATE/DELETE includes the observed revision in its WHERE clause. A stale transaction rolls back, and HTTP callers receive 409 (with the current file when the route has a file id). Metadata writes may also advance this revision. Direct bulk SQL bypasses ORM version checking and must not be used for file-content writes.

## Object save boundary

`EditorSaveRegistry` flushes mounted info, task, table/chart, and image-caption editors. AppState serializes writes per info/object/task key and waits for pending writes before AI/navigation completes. Info/table saves acknowledge captured payloads, retaining dirty status if typing continued. Object payload conflict decisions remain in the object editors; file-body three-way merging does not merge object payload JSON. This is not cross-device revision protection for individual object rows.

## Whitespace contract

Spaces and authored empty lines are content. The bridge does not trim document edges or drop authored leading paragraphs. A single initial empty paragraph remains the new-document sentinel.

Super Editor's general Markdown serializer adds hard-break syntax; its inline parser drops those breaks. Encode/decode styles per physical line instead. Two soft breaks require an explicit SPACER, because bare double newlines delimit marker blocks. Three-way merge keeps all-SPACER documents and handles end insertions once.

## Regression checks

- `test/files/sync_whitespace_regression_test.dart`: server-free whitespace round-trip and end-insert regression.
- `test/files/document_sync_test.dart`: typing during PATCH, simultaneous triggers, 409 re-merge, failure retention, and delayed adoption.
- `test/files/marker_super_editor_bridge_test.dart`, `document_three_way_test.dart`: bridge and merge cases.
- Backend `tests/files/test_file_content_revision.py`: two independent ORM sessions, stale writer rejection.

Manual checks still required: two live devices, keyboard/IME during delayed network responses, review Finish/Discard, navigation while offline, and object text followed immediately by AI.

## Spacer audit (dormant)

[`spacer_audit.dart`](spacer_audit.dart) is kept but **not wired**. To re-enable blank-line forensics:

1. Import `spacer_audit.dart` in `super_document_editor.dart` and `app_state.dart`.
2. Wire tags at these call sites:
   - `serialize` / `serialize.doc` — after `mutableDocumentToMarkerText` on document change
   - `beforePatch` — captured body in `writeDocumentVersion`
   - `afterPatch` — returned body/revision in `writeDocumentVersion`
   - `poll.inbound` — server body/revision in `readDocumentVersion`
   - `reload.in` / `reload.loaded` — `_reloadFromStored` input body and loaded `MutableDocument`
3. Search the console for `spacerAudit`. The first tag where `spacers=` drops is the stage that lost blanks.
