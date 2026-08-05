import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/note_widgets.dart';
import '../data/task.dart';
import '../tasks/task_list_surface.dart';
import './view_frame_options.dart';
import './view_frame_task_list.dart';

/// One file-like frame holding a section or topic task list.
class ViewListFrame extends StatelessWidget {
  const ViewListFrame({
    super.key,
    required this.state,
    required this.title,
    required this.tasks,
    this.onForeignDrop,
    this.sectionName,
    this.sectionFlag,
    this.topicKey,
    this.editableSection = false,
    this.onEditSection,
    this.onDeleteSection,
    this.onSectionTitleMenu,
    this.homeLists = const [],
    this.sectionOptions = const [],
    this.topicOptions = const [],
    this.accent,
    this.tintSeed = 1,
    this.isImportant = false,
    this.frameReorderMode = false,
    this.taskReorderMode = false,
    this.onTaskReorderModeChanged,
  });

  final AppState state;
  final String title;
  final List<Task> tasks;
  final TaskListForeignDrop? onForeignDrop;
  final String? sectionName;
  final String? sectionFlag;
  final String? topicKey;
  final bool editableSection;
  final Future<void> Function()? onEditSection;
  final Future<void> Function()? onDeleteSection;
  /// Right-click on the title only (edit / delete section). Task rows use the
  /// combined menu inside [ViewFrameTaskList].
  final GestureTapDownCallback? onSectionTitleMenu;
  final List<ViewFrameListOption> homeLists;
  final List<ViewSectionOption> sectionOptions;
  final List<ViewTopicOption> topicOptions;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool frameReorderMode;
  final bool taskReorderMode;
  final ValueChanged<bool>? onTaskReorderModeChanged;

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
            GestureDetector(
              onSecondaryTapDown: onSectionTitleMenu,
              child: Row(
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
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: frameReorderMode,
              child: ViewFrameTaskList(
                state: state,
                tasks: tasks,
                sectionName: sectionName,
                sectionFlag: sectionFlag,
                topicKey: topicKey,
                editableSection: editableSection,
                onEditSection: onEditSection,
                onDeleteSection: onDeleteSection,
                homeLists: homeLists,
                sectionOptions: sectionOptions,
                topicOptions: topicOptions,
                reorderMode: taskReorderMode,
                onReorderModeChanged: onTaskReorderModeChanged,
                onForeignDrop: onForeignDrop,
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

    return framed;
  }
}

/// Payload when dragging a view frame in section/topic reorder mode.
class ViewFrameDragPayload {
  const ViewFrameDragPayload({required this.frameKey});

  final String frameKey;
}
