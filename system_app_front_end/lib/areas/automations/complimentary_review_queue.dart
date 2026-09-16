import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../production_agent/pending_review_ui.dart';
import '../production_agent/agent_message_snackbar.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ux/topic/topic_appearance.dart';

/// Owns the whole walkthrough, including gaps between individual file dialogs.
Future<void> openComplimentaryReviewQueue(
  BuildContext context,
  AppState state,
  int automationId,
) async {
  if (state.reviewInteractionActive) return;
  final host = Navigator.of(context, rootNavigator: true).context;
  state.complimentaryReviewQueueOpen = true;
  try {
    final status = await state.complimentaryReviewStatus(automationId);
    final topics = (status['topics'] as List? ?? const []).whereType<Map>();
    for (final topic in topics) {
      if (!host.mounted) return;
      final name = '${topic['name'] ?? ''}';
      final accent = TopicAppearance.colorFromHex('${topic['color'] ?? ''}');
      final files = (topic['files'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      await _topicNotice(
        host,
        state,
        name,
        accent,
        files.isEmpty
            ? state.strings['reviewTopicNoChanges']
            : '${state.strings['reviewFilesPending']}: ${files.length}',
      );
      for (final file in files) {
        if (!host.mounted) return;
        final shown = await openPendingReviewForFile(
          host,
          state,
          file['id'] as int,
          automationQueue: true,
          fileName: '${file['name'] ?? ''}',
          topicName: name,
          topicAccent: accent,
        );
        if (!shown && host.mounted) {
          await _topicNotice(
            host,
            state,
            name,
            accent,
            '${file['name'] ?? ''}: ${state.strings['reviewNoChanges']}',
          );
        }
      }
      if (topic['id'] is int && status['run_id'] is int) {
        await state.acknowledgeTopicReview(topic['id'] as int, [status['run_id'] as int]);
      }
    }
    await state.completeComplimentaryReview(automationId);
  } catch (error) {
    if (host.mounted) showAgentMessageSnackBar(host, '$error');
  } finally {
    state.complimentaryReviewQueueOpen = false;
    // Refresh deferred expiry notices only after the last review route closes.
    try {
      await state.loadAutomations();
    } catch (error) {
      if (host.mounted) showAgentMessageSnackBar(host, '$error');
    }
  }
}

Future<void> _topicNotice(
  BuildContext context,
  AppState state,
  String name,
  Color accent,
  String message,
) {
  return showAppDialog<void>(
    context: context,
    isDismissible: false,
    useBottomSheet: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AppAdaptiveDialogShell(
        title: Text(name),
        headerAccent: accent,
        headerAccentIsMain: false,
        headerAccentTintAlpha: AppColors.topicDialogVeilAlpha,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(state.strings['next']),
          ),
        ],
        child: Text(message),
      ),
    ),
  );
}
