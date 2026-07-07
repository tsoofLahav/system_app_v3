import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<Topic?> showMoveFileTopicDialog({
  required BuildContext context,
  required AppState state,
  required int excludeTopicId,
}) async {
  final s = state.strings;
  final topics = state.activeTopics
      .where((topic) => topic.id != excludeTopicId)
      .toList();
  if (topics.isEmpty) {
    return null;
  }

  return showDialog<Topic>(
    context: context,
    builder: (ctx) => AppGlassDialog(
      title: Text(s['moveFileToTopic']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(s['cancel']),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: topics.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: AppColors.noteBorder.withValues(alpha: 0.35),
          ),
          itemBuilder: (context, index) {
            final topic = topics[index];
            return ListTile(
              title: Text(
                state.topicDisplayName(topic),
                style: AppTypography.noteBodyStyle,
              ),
              onTap: () => Navigator.pop(ctx, topic),
            );
          },
        ),
      ),
    ),
  );
}
