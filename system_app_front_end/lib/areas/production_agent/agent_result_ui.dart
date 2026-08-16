import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import './pending_review_ui.dart';

/// Present an agent run from its result shape — not from a copied apply_mode.
///
/// Pending review: open lookalike immediately when edited files are already
/// on screen (queue, one dialog after another); otherwise snackbar to open a
/// file. Other results → summary snackbar (+ topic reload if applied).
Future<void> presentAgentRunResult(
  BuildContext context,
  AppState state,
  Map<dynamic, dynamic> result, {
  bool reloadTopicIfApplied = true,
}) async {
  final s = state.strings;
  final changes = result['proposed_changes'] as List?;
  final hasPending = result['has_pending_review'] == true;
  final hasReview = changes != null &&
      changes.any((c) => c is Map && c['review'] != null);

  if (hasPending || hasReview) {
    if (!context.mounted) return;
    final fileIds = pendingFileIdsFromAgentResult(result);
    final visible = fileIds.where(state.isFileOnScreen).toList();
    if (visible.isNotEmpty) {
      await openPendingReviewsQueue(
        context,
        state,
        preferOrder: visible,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['aiReviewOpenFile'])),
    );
    return;
  }

  final summary = result['summary']?.toString().trim() ?? '';
  final applied = result['applied'] == true;
  final message = summary.isNotEmpty
      ? summary
      : (applied ? s['aiAgentApplied'] : s['aiAgentNoChanges']);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
  if (reloadTopicIfApplied &&
      applied &&
      state.selectedTopic != null) {
    await state.selectTopic(state.selectedTopic!);
  }
}
