import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/note_widgets.dart';
import '../data/task.dart';
import '../tasks/task_zones.dart';
import './view_task_list.dart';

/// One file-like frame holding a section or topic task list.
class ViewListFrame extends StatelessWidget {
  const ViewListFrame({
    super.key,
    required this.state,
    required this.title,
    required this.tasks,
    required this.onZonesChanged,
    this.sectionName,
    this.topicKey,
    this.frameLists = const [],
    this.accent,
    this.tintSeed = 1,
    this.isImportant = false,
    this.frameReorderMode = false,
    this.onSecondaryTapDown,
  });

  final AppState state;
  final String title;
  final List<Task> tasks;
  final ValueChanged<TaskZones> onZonesChanged;
  final String? sectionName;
  final String? topicKey;
  final List<ViewFrameListOption> frameLists;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool frameReorderMode;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final body = NoteCard(
      topicAccent: accent,
      fileId: accent == null ? null : tintSeed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (isImportant) ...[
                  AppIcon(
                    AppIcons.flag,
                    size: 14,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.noteTitleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: frameReorderMode,
              child: ViewTaskList(
                state: state,
                tasks: tasks,
                sectionName: sectionName,
                topicKey: topicKey,
                frameLists: frameLists,
                onZonesChanged: onZonesChanged,
                enabled: !frameReorderMode,
              ),
            ),
          ],
        ),
      ),
    );

    final framed = frameReorderMode
        ? DragModeFrame(
            padding: EdgeInsets.zero,
            child: body,
          )
        : body;

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: framed,
    );
  }
}

/// Payload when dragging a view frame in section/topic reorder mode.
class ViewFrameDragPayload {
  const ViewFrameDragPayload({required this.frameKey});

  final String frameKey;
}
