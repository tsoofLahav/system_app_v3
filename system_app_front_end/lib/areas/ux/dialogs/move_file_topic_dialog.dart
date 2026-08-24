import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../topic/topic_appearance.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_typography.dart';
import '../widgets/topic_emoji.dart';
import './dialog_choice_list.dart';

Future<Topic?> showMoveFileTopicDialog({
  required BuildContext context,
  required AppState state,
  required int currentTopicId,
}) {
  return showAppDialog<Topic>(
    context: context,
    builder: (_) => MoveFileTopicDialog(
      state: state,
      currentTopicId: currentTopicId,
    ),
  );
}

class MoveFileTopicDialog extends StatelessWidget {
  const MoveFileTopicDialog({
    super.key,
    required this.state,
    required this.currentTopicId,
  });

  final AppState state;
  final int currentTopicId;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final targets = state.activeTopics
        .where((topic) => topic.id != currentTopicId)
        .toList();

    return AppAdaptiveDialogShell(
      title: Text(s['moveFileToTopic']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
      child: targets.isEmpty
          ? Text(
              s['moveFileNoOtherTopics'],
              style: AppTypography.noteBodyStyle,
            )
          : DialogChoiceList(
              itemCount: targets.length,
              maxHeight: 360,
              onActivate: (i) => Navigator.pop(context, targets[i]),
              itemBuilder: (context, index, _) {
                final topic = targets[index];
                final accent = TopicAppearance.colorFromHex(topic.color);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      TopicEmoji(value: topic.icon, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.topicDisplayName(topic),
                          style: AppTypography.noteBodyStyle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
