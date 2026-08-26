import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/note_widgets.dart';
import '../data/task.dart';
import '../tasks/task_drag_data.dart';
import '../tasks/task_list_surface.dart';
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
    this.onSectionTitleMenu,
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

  /// Right-click on the title only (edit / delete section).
  final GestureTapDownCallback? onSectionTitleMenu;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool frameReorderMode;
  final bool taskReorderMode;
  final ValueChanged<bool>? onTaskReorderModeChanged;

  bool _acceptsTask(TaskDragPayload payload) =>
      payload.sourceListId == state.selectedView?.id;

  void _dropOnFrame(TaskDragPayload payload) {
    final drop = onForeignDrop;
    if (drop == null) return;
    final targetDone = payload.sourceDone;
    final indexInZone = tasks
        .where((t) => t.isDone == targetDone && t.id != payload.task.id)
        .length;
    drop(
      payload: payload,
      targetDone: targetDone,
      indexInZone: indexInZone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = NoteCard(
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
                key: ValueKey(
                  'view-frame:${sectionName ?? ''}:${topicKey ?? ''}',
                ),
                state: state,
                tasks: tasks,
                sectionName: sectionName,
                sectionFlag: sectionFlag,
                topicKey: topicKey,
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

    Widget body = card;
    if (taskReorderMode && !frameReorderMode && onForeignDrop != null) {
      body = DragTarget<TaskDragPayload>(
        onWillAcceptWithDetails: (d) => _acceptsTask(d.data),
        onAcceptWithDetails: (d) => _dropOnFrame(d.data),
        builder: (context, candidate, rejected) {
          final hot = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: hot
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      width: 1.5,
                    )
                  : null,
            ),
            child: card,
          );
        },
      );
    }

    if (frameReorderMode) {
      return DragModeFrame(
        padding: EdgeInsets.zero,
        child: body,
      );
    }
    return body;
  }
}

/// Payload when dragging a view frame in section/topic reorder mode.
class ViewFrameDragPayload {
  const ViewFrameDragPayload({required this.frameKey});

  final String frameKey;
}
