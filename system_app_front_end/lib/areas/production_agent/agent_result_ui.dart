import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../production_agent/ai_action.dart';
import './compact_undo_toast.dart';
import './pending_review_ui.dart';

/// Fire a saved AI action and show whatever it did.
///
/// Same ending as a typed prompt — a review dialog, an undo toast or a
/// summary — because a saved action is a prompt the user wrote once.
Future<void> runSavedAgentAction(
  BuildContext context,
  AppState state,
  AiAction action,
) async {
  try {
    final result = await state.runAiAction(action);
    if (!context.mounted) return;
    await presentAgentRunResult(context, state, result);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}

/// An automation run is a series: show each AI step the way a typed prompt
/// would, then a short line for the rest.
Future<void> presentAutomationRunResult(
  BuildContext context,
  AppState state,
  Map<dynamic, dynamic> result,
) async {
  final s = state.strings;
  final run = result['run'];
  if (run is! Map) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['automationFailed'])),
    );
    return;
  }
  final payload = run['result'];
  final steps = payload is Map ? payload['steps'] : null;
  if (steps is List) {
    for (final step in steps) {
      if (step is! Map) continue;
      final agent = step['agent'];
      if (agent is Map) {
        await presentAgentRunResult(context, state, agent);
        if (!context.mounted) return;
      }
    }
  }
  if (state.selectedTopic != null) {
    await state.selectTopic(state.selectedTopic!);
  }
  if (!context.mounted) return;
  final failed = run['status'] != 'completed';
  final error = '${run['error'] ?? ''}'.trim();
  final summaries = <String>[];
  if (steps is List) {
    for (final step in steps) {
      if (step is Map && step['summary'] != null) {
        summaries.add('${step['summary']}');
      }
    }
  }
  final message = failed
      ? (error.isNotEmpty ? error : s['automationFailed'])
      : (summaries.isNotEmpty ? summaries.join(' · ') : s['automationRan']);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
