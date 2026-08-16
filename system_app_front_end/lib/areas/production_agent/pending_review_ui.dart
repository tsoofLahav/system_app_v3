import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import './lookalike_review_dialog.dart';
import './pending_review_service.dart';

/// Open the lookalike pending dialog for [fileId], guarded against double-open.
Future<bool> openPendingReviewForFile(
  BuildContext context,
  AppState state,
  int fileId,
) async {
  if (!state.tryBeginPendingReviewDialog(fileId)) return false;
  try {
    final PendingReview? pending = await state.pendingReviewForFile(fileId);
    if (!context.mounted || pending == null) return false;
    await LookalikeReviewDialog.show(
      context,
      pending: pending,
      onFinish: (decisions) => state.finishPendingReview(fileId, decisions),
      onDiscard: () => state.discardPendingReview(fileId),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    state.endPendingReviewDialog(fileId);
  }
}

/// File ids from a review/pending agent result that have proposals.
List<int> pendingFileIdsFromAgentResult(Map<dynamic, dynamic> result) {
  final ids = <int>{};
  final changes = result['proposed_changes'];
  if (changes is List) {
    for (final c in changes) {
      if (c is! Map) continue;
      if (c['review'] == null && c['tool'] == 'create_object') continue;
      final id = c['file_id'];
      if (id is int) ids.add(id);
      if (id is num) ids.add(id.toInt());
    }
  }
  return ids.toList();
}
