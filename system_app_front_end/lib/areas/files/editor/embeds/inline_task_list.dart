import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../data/object_embed.dart';
import '../data/task.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../tasks/task_row.dart';
import '../tasks/task_drag_data.dart';

/// Inline task list — continuous text flow with v1-style task DnD handles only.
class InlineTaskListWidget extends StatefulWidget {
  const InlineTaskListWidget({
    super.key,
    required this.embed,
    required this.file,
    required this.state,
    required this.onRefresh,
  });

  final ObjectEmbed embed;
  final AppFile file;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  State<InlineTaskListWidget> createState() => _InlineTaskListWidgetState();
}

class _InlineTaskListWidgetState extends State<InlineTaskListWidget> {
  List<Task> get _tasks => widget.embed.tasks ?? const [];

  List<Task> get _active => _tasks.where((t) => !t.isDone).toList()
    ..sort((a, b) => a.listOrderIndex.compareTo(b.listOrderIndex));

  List<Task> get _done => _tasks.where((t) => t.isDone).toList()
    ..sort((a, b) => a.listOrderIndex.compareTo(b.listOrderIndex));

  Future<void> _createAtEnd(String title) async {
    if (widget.embed.taskListId == null) return;
    await widget.state.createTaskInList(
      widget.embed.taskListId!,
      title: title.isEmpty ? 'New task' : title,
    );
    widget.onRefresh();
  }

  Future<void> _reorderZone(List<Task> zoneTasks, int oldIndex, int newIndex) async {
    if (widget.embed.taskListId == null) return;
    if (newIndex > oldIndex) newIndex--;
    final items = List<Task>.from(zoneTasks);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final other = zoneTasks == _active ? _done : _active;
    final orderedIds = [
      if (zoneTasks == _active) ...items.map((t) => t.id),
      if (zoneTasks == _active) ...other.map((t) => t.id),
      if (zoneTasks == _done) ...other.map((t) => t.id),
      if (zoneTasks == _done) ...items.map((t) => t.id),
    ];
    await widget.state.reorderTasksInList(widget.embed.taskListId!, orderedIds);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InlineTaskZone(
          tasks: _active,
          done: false,
          taskListId: widget.embed.taskListId ?? 0,
          state: widget.state,
          onRefresh: widget.onRefresh,
          onReorder: (o, n) => _reorderZone(_active, o, n),
        ),
        _InlineTaskZone(
          tasks: _done,
          done: true,
          taskListId: widget.embed.taskListId ?? 0,
          state: widget.state,
          onRefresh: widget.onRefresh,
          onReorder: (o, n) => _reorderZone(_done, o, n),
        ),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Add task…',
            isDense: true,
            border: InputBorder.none,
          ),
          style: AppTypography.noteBodyStyle,
          onSubmitted: _createAtEnd,
        ),
      ],
    );
  }
}

class _InlineTaskZone extends StatelessWidget {
  const _InlineTaskZone({
    required this.tasks,
    required this.done,
    required this.taskListId,
    required this.state,
    required this.onRefresh,
    required this.onReorder,
  });

  final List<Task> tasks;
  final bool done;
  final int taskListId;
  final AppState state;
  final VoidCallback onRefresh;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i <= tasks.length; i++) ...[
          if (tasks.length > 1)
            _DropSlot(
              taskListId: taskListId,
              done: done,
              index: i,
              tasks: tasks,
              onDrop: (payload, targetIndex) async {
                final fromIndex = tasks.indexWhere((t) => t.id == payload.task.id);
                if (fromIndex < 0 || fromIndex == targetIndex) return;
                await onReorder(fromIndex, targetIndex);
              },
            ),
          if (i < tasks.length)
            _DraggableTaskRow(
              task: tasks[i],
              index: i,
              taskListId: taskListId,
              done: done,
              state: state,
              onRefresh: onRefresh,
            ),
        ],
      ],
    );
  }
}

class _DraggableTaskRow extends StatelessWidget {
  const _DraggableTaskRow({
    required this.task,
    required this.index,
    required this.taskListId,
    required this.done,
    required this.state,
    required this.onRefresh,
  });

  final Task task;
  final int index;
  final int taskListId;
  final bool done;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final payload = TaskDragPayload(
      task: task,
      sourceListId: taskListId,
      sourceDone: done,
    );
    return LongPressDraggable<TaskDragPayload>(
      data: payload,
      feedback: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(task.title, style: AppTypography.taskRowStyle),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _row(context, showHandle: true)),
      child: _row(context, showHandle: true),
    );
  }

  Widget _row(BuildContext context, {required bool showHandle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHandle)
          MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, end: 4),
              child: SizedBox(
                width: 20,
                height: AppTypography.taskRowLineHeight,
                child: Center(
                  child: AppIcon(
                    AppIcons.drag,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: TaskRow(
            task: task,
            state: state,
            onToggle: () async {
              await state.toggleTaskStatus(task);
              onRefresh();
            },
            onTitleChanged: (title) async {
              await state.updateTaskTitle(task, title);
              onRefresh();
            },
            onDelete: () async {
              await state.deleteTask(task);
              onRefresh();
            },
          ),
        ),
      ],
    );
  }
}

class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.taskListId,
    required this.done,
    required this.index,
    required this.tasks,
    required this.onDrop,
  });

  final int taskListId;
  final bool done;
  final int index;
  final List<Task> tasks;
  final Future<void> Function(TaskDragPayload payload, int targetIndex) onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        if (payload.sourceListId != taskListId || payload.sourceDone != done) {
          return false;
        }
        final fromIndex = tasks.indexWhere((t) => t.id == payload.task.id);
        return fromIndex >= 0 && fromIndex != index;
      },
      onAcceptWithDetails: (details) => onDrop(details.data, index),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 6 : 2,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}
