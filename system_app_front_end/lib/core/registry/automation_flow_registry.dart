import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/task.dart';
import '../../design_system/app_typography.dart';
import '../../shared/change_review/change_review_dialog.dart';
import '../models/change_set.dart';

/// Maps automation companion [Task.flowKey] values to in-app follow-up flows.
abstract final class AutomationFlowRegistry {
  static Future<bool> run({
    required BuildContext context,
    required AppState state,
    required Task task,
  }) async {
    switch (task.flowKey) {
      case 'process_update_review':
        return _runProcessUpdateReview(context: context, state: state, task: task);
      default:
        return false;
    }
  }

  static Future<bool> _runProcessUpdateReview({
    required BuildContext context,
    required AppState state,
    required Task task,
  }) async {
    final rawId = task.companionPayload['proposal_id'];
    final proposalId = rawId is int
        ? rawId
        : (rawId is num ? rawId.toInt() : null);
    if (proposalId == null) return false;

    final proposal = await state.fetchAiProposal(proposalId);
    if (!context.mounted) return false;

    if (proposal.proposalType == 'process_refresh_skipped') {
      final message = proposal.payload['message']?.toString() ??
          state.strings['processRefreshSkipped'];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(state.strings['processRefreshSkipped']),
          content: Text(message, style: AppTypography.noteBodyStyle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(state.strings['dismiss']),
            ),
          ],
        ),
      );
      if (!context.mounted) return false;
      await state.rejectAiProposal(
        proposal,
        companionTaskId: task.companionTaskId,
      );
      return true;
    }

    final raw = proposal.payload['change_set'];
    if (raw is! Map<String, dynamic>) return false;

    final decisions = await showChangeReviewDialog(
      context: context,
      strings: state.strings,
      changeSet: ChangeSet.fromJson(raw),
      title: state.strings['processUpdateReview'],
    );
    if (decisions == null) return false;

    await state.finalizeProcessUpdate(
      proposal,
      decisions,
      companionTaskId: task.companionTaskId,
    );
    return true;
  }
}
