import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ux/topic/topic_appearance.dart';
import 'pending_review_ui.dart';
import 'agent_message_snackbar.dart';

/// A topic visit reviews all its files, including files outside the visible layout.
Future<void> openTopicReviewQueue(BuildContext context, AppState state, int topicId) async {
  if (state.reviewInteractionActive) return;
  final host = Navigator.of(context, rootNavigator: true).context;
  state.complimentaryReviewQueueOpen = true;
  try {
    final data = await state.topicPendingReviews(topicId);
    final topic = data['topic'] as Map;
    final files = (data['files'] as List? ?? const []).whereType<Map>().toList();
    final runIds = (data['run_ids'] as List? ?? const []).cast<int>();
    final accent = TopicAppearance.colorFromHex('${topic['color'] ?? ''}');
    if (!host.mounted) return;
    if (files.isEmpty && runIds.isNotEmpty) {
      await showAppDialog<void>(context: host, isDismissible: false,
        builder: (ctx) => PopScope(canPop: false, child: AppAdaptiveDialogShell(
          title: Text('${topic['name']}'), headerAccent: accent,
          headerAccentTintAlpha: AppColors.topicDialogVeilAlpha,
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(state.strings['reviewFinish']))],
          child: Text(state.strings['reviewTopicNoChanges']),
        )));
    }
    for (final file in files) {
      if (!host.mounted) return;
      await openPendingReviewForFile(host, state, file['id'] as int,
        automationQueue: true, fileName: '${file['name']}',
        topicName: '${topic['name']}', topicAccent: accent);
    }
    if (files.isNotEmpty || runIds.isNotEmpty) {
      await state.acknowledgeTopicReview(topicId, runIds);
    }
  } catch (error) {
    if (host.mounted) showAgentMessageSnackBar(host, '$error');
  } finally {
    state.complimentaryReviewQueueOpen = false;
    try { await state.loadAutomations(); }
    catch (error) { if (host.mounted) showAgentMessageSnackBar(host, '$error'); }
  }
}
