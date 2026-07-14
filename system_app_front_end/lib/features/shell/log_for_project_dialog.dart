import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/widgets/topic_emoji.dart';

Future<Topic?> showLogForProjectDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showDialog<Topic>(
    context: context,
    builder: (ctx) => LogForProjectDialog(state: state),
  );
}

class LogForProjectDialog extends StatelessWidget {
  const LogForProjectDialog({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final projects = state.projects;

    return AppGlassDialog(
      title: Text(s['logForProject']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
      child: SizedBox(
        width: 320,
        child: projects.isEmpty
            ? Text(s['noProjectsAvailable'], style: AppTypography.noteBodyStyle)
            : ListView.builder(
                shrinkWrap: true,
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final accent = TopicAppearance.colorFromHex(project.color);
                  return ListTile(
                    leading: TopicEmoji(value: project.icon, size: 18),
                    title: Text(
                      state.topicDisplayName(project),
                      style: AppTypography.noteBodyStyle.copyWith(
                        color: accent.withValues(alpha: 0.92),
                      ),
                    ),
                    onTap: () => Navigator.pop(context, project),
                  );
                },
              ),
      ),
    );
  }
}
