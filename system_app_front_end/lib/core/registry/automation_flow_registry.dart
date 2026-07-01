import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/task.dart';
import '../../features/shell/process_update_batch_dialog.dart';

/// Maps automation companion [Task.flowKey] values to in-app follow-up flows.
abstract final class AutomationFlowRegistry {
  static Future<bool> run({
    required BuildContext context,
    required AppState state,
    required Task task,
  }) async {
    if (!task.hasAutomationFlow) return false;

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
    final companions = await state.fetchPendingCompanionsForTask(task.id);
    if (!context.mounted || companions.isEmpty) return false;

    final completed = await showProcessUpdateBatchDialog(
      context: context,
      state: state,
      companions: companions,
    );
    if (completed && state.selectedViewType != null) {
      await state.refreshCurrentView();
    }
    return completed;
  }
}
