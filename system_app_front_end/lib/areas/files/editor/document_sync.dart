import 'dart:async';

import 'document_three_way.dart';

/// An inseparable server body/revision pair.
class DocumentVersion {
  const DocumentVersion(this.body, this.revision);
  final String body;
  final int revision;
}

class DocumentWriteConflict implements Exception {
  const DocumentWriteConflict();
}

class DocumentSyncNeedsReview implements Exception {
  const DocumentSyncNeedsReview();
}

/// One durable-in-session coordinator per file, independent of widget lifetime.
/// Only this object advances the merge baseline or acknowledges a draft.
class DocumentSync {
  DocumentSync(DocumentVersion initial)
    : baseline = initial,
      draft = initial.body;

  DocumentVersion baseline;
  String draft;
  int generation = 0;
  Future<void>? _running;
  bool get dirty => draft != baseline.body;
  bool get running => _running != null;

  void edit(String body) {
    if (body == draft) return;
    draft = body;
    generation++;
  }

  Future<void> synchronize({
    required Future<DocumentVersion> Function() read,
    required Future<DocumentVersion> Function(String, int) write,
    required Future<String?> Function(ThreeWayResult) review,
    Future<void> Function()? beforeAdopt,
    void Function()? onAdopt,
  }) {
    if (_running != null) return _running!;
    final done = Completer<void>();
    _running = done.future;
    () async {
      try {
        await _run(
          read: read,
          write: write,
          review: review,
          beforeAdopt: beforeAdopt,
          onAdopt: onAdopt,
        );
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _running = null;
      }
    }();
    return done.future;
  }

  Future<void> _run({
    required Future<DocumentVersion> Function() read,
    required Future<DocumentVersion> Function(String, int) write,
    required Future<String?> Function(ThreeWayResult) review,
    Future<void> Function()? beforeAdopt,
    void Function()? onAdopt,
  }) async {
    while (true) {
      final server = await read();
      if (server.revision < baseline.revision) return;
      final captured = draft;
      final epoch = generation;
      final merged = await _merge(baseline.body, captured, server.body, review);
      // A dialog/network wait must not consume edits made after its snapshot.
      if (generation != epoch) continue;
      DocumentVersion saved;
      if (merged == server.body) {
        saved = server;
      } else {
        try {
          saved = await write(merged, server.revision);
        } on DocumentWriteConflict {
          // Re-read and re-merge, never merely substitute a new revision.
          continue;
        }
      }
      // Carry edits made during PATCH onto the acknowledged result. If the
      // result only contains our captured draft this is an exact fast path.
      while (true) {
        final currentEpoch = generation;
        final next = generation == epoch
            ? saved.body
            : await _merge(captured, draft, saved.body, review);
        await beforeAdopt?.call();
        if (generation != currentEpoch) continue;
        baseline = saved;
        edit(next);
        onAdopt?.call();
        break;
      }
      if (!dirty) return;
    }
  }

  Future<String> _merge(
    String base,
    String local,
    String server,
    Future<String?> Function(ThreeWayResult) review,
  ) async {
    // Preserve byte-identical one-sided content; no normalization on sync.
    if (local == server || server == base) return local;
    if (local == base) return server;
    final result = threeWayMarkerText(base: base, local: local, server: server);
    if (!result.hasConflicts) return result.merged;
    final resolved = await review(result);
    if (resolved == null) throw const DocumentSyncNeedsReview();
    return resolved;
  }
}
