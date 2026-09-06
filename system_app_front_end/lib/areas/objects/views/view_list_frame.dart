import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/note_widgets.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../tasks/task_drag_data.dart';
import '../tasks/task_list_surface.dart';
import './view_frame_task_list.dart';

/// One file-like frame holding a section or topic task list.
class ViewListFrame extends StatefulWidget {
  const ViewListFrame({
    super.key,
    required this.state,
    required this.title,
    required this.tasks,
    this.onForeignDrop,
    this.sectionName,
    this.sectionFlag,
    this.topicKey,
    this.onEditSection,
    this.onOpenSectionAutomation,
    this.onDeleteSection,
    this.accent,
    this.tintSeed = 1,
    this.isImportant = false,
    this.attention = false,
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

  /// Named-section chrome (null on topic frames / Uncategorized).
  final Future<void> Function()? onEditSection;
  final Future<void> Function()? onOpenSectionAutomation;
  final Future<void> Function()? onDeleteSection;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool attention;
  final bool frameReorderMode;
  final bool taskReorderMode;
  final ValueChanged<bool>? onTaskReorderModeChanged;

  @override
  State<ViewListFrame> createState() => _ViewListFrameState();
}

class _ViewListFrameState extends State<ViewListFrame> {
  final _listKey = GlobalKey<ViewFrameTaskListState>();

  bool get _hasSectionChrome =>
      widget.onEditSection != null ||
      widget.onOpenSectionAutomation != null ||
      widget.onDeleteSection != null;

  bool _acceptsTask(TaskDragPayload payload) =>
      payload.sourceListId == widget.state.selectedView?.id;

  void _dropOnFrame(TaskDragPayload payload) {
    final drop = widget.onForeignDrop;
    if (drop == null) return;
    final targetDone = payload.sourceDone;
    final indexInZone = widget.tasks
        .where((t) => t.isDone == targetDone && t.id != payload.task.id)
        .length;
    drop(
      payload: payload,
      targetDone: targetDone,
      indexInZone: indexInZone,
    );
  }

  Future<void> _addTask() async {
    await _listKey.currentState?.addTask();
  }

  Future<void> _onTitleMenu(TapDownDetails details) async {
    final s = widget.state.strings;
    final action = await AppContextMenu.show(
      context: context,
      globalPosition: details.globalPosition,
      isRtl: s.isRtl,
      entries: [
        AppContextMenuItem(
          value: 'add_task',
          label: s['addTask'],
        ),
        if (_hasSectionChrome) ...[
          const AppContextMenuDivider(),
          if (widget.onEditSection != null)
            AppContextMenuItem(value: 'edit', label: s['editSection']),
          if (widget.onOpenSectionAutomation != null)
            AppContextMenuItem(
              value: 'automation',
              label: s['openSectionAutomation'],
            ),
          if (widget.onDeleteSection != null)
            AppContextMenuItem(
              value: 'delete',
              label: s['deleteSection'],
              destructive: true,
            ),
        ],
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'add_task') {
      await _addTask();
      return;
    }
    if (action == 'edit') {
      await widget.onEditSection?.call();
      return;
    }
    if (action == 'automation') {
      await widget.onOpenSectionAutomation?.call();
      return;
    }
    if (action == 'delete') {
      await widget.onDeleteSection?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = NoteCard(
      topicAccent: widget.accent,
      fileId: widget.accent == null ? null : widget.tintSeed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onDoubleTap: () => unawaited(_addTask()),
              onSecondaryTapDown: (d) => unawaited(_onTitleMenu(d)),
              child: Row(
                children: [
                  if (widget.isImportant) ...[
                    AppIcon(
                      AppIcons.flag,
                      size: 14,
                      color: AppColors.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.noteTitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.attention)
                    Tooltip(
                      message: widget.state.strings['sectionAttention'],
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.destructive,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: widget.frameReorderMode,
              child: ViewFrameTaskList(
                key: _listKey,
                state: widget.state,
                tasks: widget.tasks,
                sectionName: widget.sectionName,
                sectionFlag: widget.sectionFlag,
                topicKey: widget.topicKey,
                reorderMode: widget.taskReorderMode,
                onReorderModeChanged: widget.onTaskReorderModeChanged,
                onForeignDrop: widget.onForeignDrop,
                enabled: !widget.frameReorderMode,
              ),
            ),
          ],
        ),
      ),
    );

    Widget body = card;
    if (widget.taskReorderMode &&
        !widget.frameReorderMode &&
        widget.onForeignDrop != null) {
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

    if (widget.frameReorderMode) {
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
