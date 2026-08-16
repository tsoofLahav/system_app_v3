import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import './lookalike_review_dialog.dart';
import './pending_review_service.dart';

/// Open the lookalike pending dialog for [fileId], guarded against double-open.
///
/// After the dialog closes (Finish or Discard), opens the next on-screen file
/// that still has a pending review (multi-file runs).
Future<bool> openPendingReviewForFile(
  BuildContext context,
  AppState state,
  int fileId, {
  List<int>? preferOrder,
}) async {
  if (!state.tryBeginPendingReviewDialog(fileId)) return false;
  var showed = false;
  try {
    final PendingReview? pending = await state.pendingReviewForFile(fileId);
    if (!context.mounted || pending == null) return false;
    showed = true;
    await LookalikeReviewDialog.show(
      context,
      pending: pending,
      onFinish: (decisions) => state.finishPendingReview(fileId, decisions),
      onDiscard: () => state.discardPendingReview(fileId),
    );
  } catch (_) {
    return false;
  } finally {
    state.endPendingReviewDialog(fileId);
  }

  if (showed && context.mounted) {
    await _openNextOnScreenPending(
      context,
      state,
      preferOrder: preferOrder,
      skipFileId: fileId,
    );
  }
  return showed;
}

/// Start the on-screen pending queue (agent result or multi-pane).
///
/// Opens the first pending file; [openPendingReviewForFile] chains the rest.
Future<void> openPendingReviewsQueue(
  BuildContext context,
  AppState state, {
  List<int>? preferOrder,
}) async {
  await _openNextOnScreenPending(
    context,
    state,
    preferOrder: preferOrder,
  );
}

Future<void> _openNextOnScreenPending(
  BuildContext context,
  AppState state, {
  List<int>? preferOrder,
  int? skipFileId,
}) async {
  for (final id in _orderedOnScreenFileIds(state, preferOrder)) {
    if (id == skipFileId) continue;
    if (!context.mounted) return;
    if (!state.isFileOnScreen(id)) continue;
    try {
      final pending = await state.pendingReviewForFile(id);
      if (pending == null) continue;
    } catch (_) {
      continue;
    }
    if (!context.mounted) return;
    await openPendingReviewForFile(
      context,
      state,
      id,
      preferOrder: preferOrder,
    );
    return;
  }
}

List<int> _orderedOnScreenFileIds(AppState state, List<int>? preferOrder) {
  final ordered = <int>[];
  final seen = <int>{};
  void add(int id) {
    if (seen.add(id)) ordered.add(id);
  }

  for (final id in preferOrder ?? const <int>[]) {
    add(id);
  }
  for (final f in state.selectedDetail?.files ?? const []) {
    add(f.id);
  }
  return ordered;
}

/// File ids from a review/pending agent result that have proposals.
List<int> pendingFileIdsFromAgentResult(Map<dynamic, dynamic> result) {
  final ids = <int>{};
  final changes = result['proposed_changes'];
  if (changes is List) {
    for (final c in changes) {
      if (c is! Map) continue;
      if (c['review'] == null) continue;
      final id = c['file_id'];
      if (id is int) ids.add(id);
      if (id is num) ids.add(id.toInt());
    }
  }
  return ids.toList();
}
