import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../tasks/task_drag_data.dart';
import '../tasks/task_row.dart';
import '../tasks/task_zones.dart';

/// Active/Done task list for one view frame — mark/unmark + Reorder Mode.
class ViewTaskList extends StatefulWidget {
  const ViewTaskList({
    super.key,
    required this.state,
    required this.tasks,
    required this.onZonesChanged,
    this.enabled = true,
  });

  final AppState state;
  final List<Task> tasks;
  final ValueChanged<TaskZones> onZonesChanged;
  final bool enabled;

  @override
  State<ViewTaskList> createState() => _ViewTaskListState();
}

class _ViewTaskListState extends State<ViewTaskList> {
  var _reorderMode = false;

  List<Task> get _tasks => widget.tasks;

  void _setReorderMode(bool value) {
    if (_reorderMode == value) return;
    setState(() => _reorderMode = value);
    if (value) FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onDrop({
    required TaskDragPayload payload,
    required bool targetDone,
    required int indexInZone,
  }) {
    final zones = TaskZones.fromOrdered(_tasks);
    final next = zones.moved(
      taskId: payload.task.id,
      targetDone: targetDone,
      indexInZone: indexInZone,
    );
    if (next.orderedIds.join() == zones.orderedIds.join() &&
        payload.sourceDone == targetDone) {
      return;
    }
    widget.onZonesChanged(next);
  }

  Future<void> _toggle(Task task) async {
    final zones = TaskZones.fromOrdered(_tasks);
    final targetDone = !task.isDone;
    final next = zones.moved(
      taskId: task.id,
      targetDone: targetDone,
      indexInZone: targetDone ? zones.done.length : zones.active.length,
    );
    widget.onZonesChanged(next);
  }

  Future<void> _showTaskMenu(Offset globalPosition, Task task) async {
    final s = widget.state.strings;
    final action = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      isRtl: s.isRtl,
      entries: [
        AppContextMenuItem(
          value: 'reorder',
          label: s['reorderTasks'],
        ),
      ],
    );
    if (action == 'reorder') _setReorderMode(true);
  }

  Widget _zoneLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: AppTypography.metaStyle.copyWith(
          color: AppColors.textHint,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _dropGap({required bool targetDone, required int indexInZone}) {
    if (!_reorderMode) return const SizedBox(height: 2);
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _onDrop(
        payload: d.data,
        targetDone: targetDone,
        indexInZone: indexInZone,
      ),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: hot ? 12 : 4,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: hot
                ? AppColors.glassTint.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: hot ? AppGlassStyle.dragModeBorder : null,
          ),
        );
      },
    );
  }

  Widget _compactChip(Task task, {required bool glass}) {
    final title = task.title.trim().isEmpty
        ? widget.state.strings['newTaskHint']
        : task.title;
    final style = AppTypography.taskRowStyle.copyWith(
      decoration: task.isDone ? TextDecoration.lineThrough : null,
      color: task.isDone ? AppColors.textHint : null,
    );
    final body = Text(title, style: style);
    final chip = glass ? DragModeFrame.chip(child: body) : body;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: chip,
    );
  }

  Widget _taskTile(Task task) {
    final zones = TaskZones.fromOrdered(_tasks);
    final inDone = task.isDone;
    final zone = inDone ? zones.done : zones.active;
    final zoneIndex = zone.indexWhere((t) => t.id == task.id);
    final indexInZone = zoneIndex < 0 ? zone.length : zoneIndex;

    if (_reorderMode) {
      final framed = _compactChip(task, glass: true);
      return DragTarget<TaskDragPayload>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _onDrop(
          payload: d.data,
          targetDone: inDone,
          indexInZone: indexInZone,
        ),
        builder: (context, candidate, rejected) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (candidate.isNotEmpty)
                Container(
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: AppColors.glassTint.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Draggable<TaskDragPayload>(
                data: TaskDragPayload(
                  task: task,
                  sourceListId: task.taskListId ?? 0,
                  sourceDone: task.isDone,
                ),
                feedback: Material(
                  color: Colors.transparent,
                  child: _compactChip(task, glass: true),
                ),
                childWhenDragging: Opacity(opacity: 0.28, child: framed),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: framed,
                ),
              ),
            ],
          );
        },
      );
    }

    return GestureDetector(
      onSecondaryTapDown: widget.enabled
          ? (d) => unawaited(_showTaskMenu(d.globalPosition, task))
          : null,
      child: TaskRow(
        task: task,
        state: widget.state,
        onToggle: widget.enabled ? () => unawaited(_toggle(task)) : () {},
        onTitleChanged: widget.enabled
            ? (title) => unawaited(widget.state.updateTaskTitle(task, title))
            : null,
        readOnly: !widget.enabled,
        toggleEnabled: widget.enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final zones = TaskZones.fromOrdered(_tasks);
    if (_tasks.isEmpty) {
      return Text(
        s['noTasks'],
        style: AppTypography.metaStyle.copyWith(color: AppColors.textHint),
      );
    }

    final list = Column(
      crossAxisAlignment:
          _reorderMode ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
      children: [
        _zoneLabel(s['tasksActive']),
        for (final t in zones.active) _taskTile(t),
        _dropGap(targetDone: false, indexInZone: zones.active.length),
        if (zones.done.isNotEmpty) ...[
          _zoneLabel(s['tasksDone']),
          for (final t in zones.done) _taskTile(t),
          _dropGap(targetDone: true, indexInZone: zones.done.length),
        ],
      ],
    );

    if (!_reorderMode) return list;
    return TapRegion(
      onTapOutside: (_) => _setReorderMode(false),
      child: list,
    );
  }
}
