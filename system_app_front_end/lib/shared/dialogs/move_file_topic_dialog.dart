import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../widgets/topic_emoji.dart';

Future<Topic?> showMoveFileTopicDialog({
  required BuildContext context,
  required AppState state,
  required int currentTopicId,
}) {
  return showDialog<Topic>(
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

    return AppGlassDialog(
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
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360, maxWidth: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: targets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final topic = targets[index];
                  final accent = TopicAppearance.colorFromHex(topic.color);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: TopicEmoji(value: topic.icon, size: 20),
                    title: Text(
                      state.topicDisplayName(topic),
                      style: AppTypography.noteBodyStyle,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: accent.withValues(alpha: 0.35),
                      ),
                    ),
                    onTap: () => Navigator.pop(context, topic),
                  );
                },
              ),
            ),
    );
  }
}
