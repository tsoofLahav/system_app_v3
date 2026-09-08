import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../files/editor/document_editor_controller.dart';
import '../production_agent/ai_action.dart';
import './agent_message_snackbar.dart';
import './compact_undo_toast.dart';
import './pending_review_ui.dart';

export './agent_message_snackbar.dart';

/// Fire a saved AI action and show whatever it did.
///
/// Same ending as a typed prompt — a review dialog, an undo toast or a
/// summary — because a saved action is a prompt the user wrote once.
/// Cancel waits for the run to return, then drops the result instead.
Future<void> runSavedAgentAction(
  BuildContext context,
  AppState state,
  AiAction action,
) async {
  if (state.aiRunning) return;
  try {
    final selectedMark = DocumentEditorRegistry.captureMarkedTextForAgent();
    notifySelectedTextTruncation(context, state.strings, selectedMark);
    final result = await state.runAiAction(
      action,
      selectedText: selectedMark?.text,
    );
    if (state.aiCancelRequested) {
      await discardCancelledAgentRun(state, result);
      return;
    }
    if (!context.mounted) return;
    await presentAgentRunResult(context, state, result);
  } catch (e) {
    if (state.aiCancelRequested) {
      state.endAiRun();
      return;
    }
    if (!context.mounted) return;
    showAgentMessageSnackBar(context, e.toString());
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
    showAgentMessageSnackBar(context, s['automationFailed']);
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
  // Membership (create/archive) without blanking every open editor.
  await state.softRefreshOpenTopicFiles();
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
  showAgentMessageSnackBar(context, message);
}

/// Wait out a cancelled run, then drop its result: no review, undo toast, or
/// summary. Direct-apply writes are rolled back when undo cards exist; review
/// proposals are discarded so they do not open later.
Future<void> discardCancelledAgentRun(
  AppState state,
  Map<dynamic, dynamic> result,
) async {
  try {
    await _silentDiscardAgentResult(state, result);
  } finally {
    state.endAiRun();
  }
}

Future<void> discardCancelledAutomationRun(
  AppState state,
  Map<dynamic, dynamic> result,
) async {
  try {
    for (final agent in agentResultsFromAutomationRun(result)) {
      await _silentDiscardAgentResult(state, agent);
    }
  } finally {
    state.endAiRun();
  }
}

Future<void> _silentDiscardAgentResult(
  AppState state,
  Map<dynamic, dynamic> result,
) async {
  for (final fileId in pendingFileIdsFromAgentResult(result)) {
    try {
      await state.discardPendingReview(fileId);
    } catch (_) {}
  }
  state.dismissAgentReview();
  for (final card in undoCardsFromAgentResult(result)) {
    try {
      await state.undoDirectApply(
        fileId: card.fileId,
        oldDocumentJson: card.oldDocumentJson,
        topicId: card.topicId,
        reloadTopic: false,
      );
    } catch (_) {}
  }
}

/// Agent step payloads inside an automation run result.
List<Map<dynamic, dynamic>> agentResultsFromAutomationRun(
  Map<dynamic, dynamic> result,
) {
  final run = result['run'];
  if (run is! Map) return const [];
  final payload = run['result'];
  final steps = payload is Map ? payload['steps'] : null;
  if (steps is! List) return const [];
  final agents = <Map<dynamic, dynamic>>[];
  for (final step in steps) {
    if (step is! Map) continue;
    final agent = step['agent'];
    if (agent is Map) agents.add(agent);
  }
  return agents;
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
    showAgentMessageSnackBar(context, s['aiReviewOpenFile']);
    return;
  }

  final applied = result['applied'] == true;
  final undoCards = undoCardsFromAgentResult(result);
  if (applied && undoCards.isNotEmpty) {
    if (reloadTopicIfApplied) {
      await state.reloadAgentTouchedFiles(undoCards.map((c) => c.fileId));
    }
    if (!context.mounted) return;
    await showCompactUndoQueue(context, state, undoCards);
    return;
  }

  final error = result['error']?.toString().trim() ?? '';
  final summary = result['summary']?.toString().trim() ?? '';
  final message = error.isNotEmpty
      ? error
      : (summary.isNotEmpty
          ? summary
          : (applied ? s['aiAgentApplied'] : s['aiAgentNoChanges']));
  if (!context.mounted) return;
  showAgentMessageSnackBar(context, message);
  if (reloadTopicIfApplied && applied) {
    await state.reloadAgentTouchedFiles(appliedFileIdsFromAgentResult(result));
  }
}

/// File ids the agent wrote when [result] was applied (no pending review).
List<int> appliedFileIdsFromAgentResult(Map<dynamic, dynamic> result) {
  final out = <int>{};
  for (final card in undoCardsFromAgentResult(result)) {
    if (card.fileId != 0) out.add(card.fileId);
  }
  final changes = result['proposed_changes'];
  if (changes is List) {
    for (final change in changes) {
      if (change is! Map) continue;
      if (change['applied'] == false) continue;
      final id = change['file_id'];
      if (id is int && id != 0) out.add(id);
    }
  }
  return out.toList();
}
