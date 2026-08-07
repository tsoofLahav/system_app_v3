import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import './text_diff_dialog.dart';

/// Present an agent run from its result shape — not from a copied apply_mode.
///
/// Review proposals → diff dialog; otherwise snackbar (+ topic reload if applied).
Future<void> presentAgentRunResult(
  BuildContext context,
  AppState state,
  Map<dynamic, dynamic> result, {
  bool reloadTopicIfApplied = true,
}) async {
  final s = state.strings;
  final changes = result['proposed_changes'] as List?;
  final hasReview = changes != null &&
      changes.any((c) => c is Map && c['review'] != null);

  if (hasReview && changes != null) {
    final first = changes.firstWhere(
          (c) => c is Map && c['review'] != null,
        ) as Map;
    final review = first['review'] as Map?;
    final diff = review?['diff_hunks']?.toString() ?? '';
    final apply = await TextDiffDialog.show(
      context,
      title: s['reviewChanges'] ?? 'Review changes',
      diffHunks: diff,
    );
    if (!context.mounted) return;
    if (apply == true) {
      await state.applyAgentReview();
    } else {
      state.dismissAgentReview();
    }
    return;
  }

  final summary = result['summary']?.toString().trim() ?? '';
  final applied = result['applied'] == true;
  final message = summary.isNotEmpty
      ? summary
      : (applied
          ? (s['aiAgentApplied'] ?? 'Changes applied.')
          : (s['aiAgentNoChanges'] ?? 'No file changes.'));
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
