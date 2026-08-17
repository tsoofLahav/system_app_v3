import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../automations/automation.dart';
import './compact_undo_toast.dart';
import './pending_review_ui.dart';

/// Fire a saved AI action and show whatever it did.
///
/// Same ending as a typed prompt — a review dialog, an undo toast or a
/// summary — because a saved action is a prompt the user wrote once.
Future<void> runSavedAgentAction(
  BuildContext context,
  AppState state,
  Automation automation,
) async {
  try {
    final result = await state.runAutomationRecord(automation);
    if (!context.mounted) return;
    final agent = result['agent'];
    if (agent is! Map) return;
    await presentAgentRunResult(context, state, agent);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}

/// Present an agent run from its result shape — not from a copied apply_mode.
///
/// Pending review: open lookalike when edited files are on screen (queued).
/// Direct apply: compact undo toast queue (even off that file’s page).
/// Else: summary snackbar.
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

  final applied = result['applied'] == true;
  final undoCards = undoCardsFromAgentResult(result);
  if (applied && undoCards.isNotEmpty) {
    if (reloadTopicIfApplied && state.selectedTopic != null) {
      await state.selectTopic(state.selectedTopic!);
    }
    if (!context.mounted) return;
    await showCompactUndoQueue(context, state, undoCards);
    return;
  }

  final summary = result['summary']?.toString().trim() ?? '';
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
