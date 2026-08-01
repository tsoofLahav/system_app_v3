import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/app_state.dart';
import '../document_text_flow.dart';
import '../../rich_text/block_text_actions.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/formatted_text_field.dart';
import '../../rich_text/span_text_editing_controller.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/app_typography.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/data/task.dart';
import '../../../objects/tasks/task_drag_data.dart';
import '../../../objects/tasks/task_mark.dart';
import '../../../objects/tasks/task_zones.dart';

/// Task list as a document list: Active then Done, checkbox gutter, optimistic
/// drag-reorder. Empty titles stay blank (hint only).
class InlineTaskListWidget extends StatefulWidget {
  const InlineTaskListWidget({
    super.key,
    required this.embed,
    required this.blockId,
    required this.state,
    required this.onRefresh,
    this.onFocus,
    this.onExitBelow,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppState state;
  final VoidCallback onRefresh;
  final VoidCallback? onFocus;
  final ValueChanged<int>? onExitBelow;

  @override
  State<InlineTaskListWidget> createState() => _InlineTaskListWidgetState();
}

class _InlineTaskListWidgetState extends State<InlineTaskListWidget> {
  final _controllers = <SpanTextEditingController>[];
  final _focusNodes = <FocusNode>[];
  final _taskIds = <int?>[];
  final _done = <bool>[];
  final _saveTimers = <Timer?>[];
  int? _pendingFocusIndex;
  var _ensuringSeed = false;
  var _persisting = false;
  List<Task>? _optimistic;

  List<Task> get _remoteTasks => TaskZones.fromTasks(
        widget.embed.tasks ?? const <Task>[],
      ).all;

  List<Task> get _displayTasks => _optimistic ?? _remoteTasks;

  int get _activeCount =>
      _displayTasks.where((t) => !t.isDone).length;

  @override
  void initState() {
    super.initState();
    _syncFromTasks(_displayTasks);
    if (_taskIds.isEmpty || _taskIds.every((id) => id == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureSeedTask());
      });
    }
  }

  @override
  void didUpdateWidget(InlineTaskListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_persisting) return;
    if (oldWidget.embed.id != widget.embed.id) {
      _optimistic = null;
      _disposeRows();
      _syncFromTasks(_displayTasks);
      return;
    }
    if (_optimistic != null) {
      // Keep optimistic order until remote catches up.
      if (_idsMatch(_optimistic!, _remoteTasks)) {
        _optimistic = null;
      } else {
        return;
      }
    }
    if (_localMatchesRemote()) return;
    final focusIdx =
        _pendingFocusIndex ?? _focusNodes.indexWhere((f) => f.hasFocus);
    _disposeRows();
    _syncFromTasks(_displayTasks);
    if (focusIdx >= 0 && focusIdx < _focusNodes.length) {
      _pendingFocusIndex = focusIdx;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyPendingFocus());
    }
  }

  bool _idsMatch(List<Task> a, List<Task> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].isDone != b[i].isDone) return false;
    }
    return true;
  }

  bool _localMatchesRemote() {
    final tasks = _displayTasks;
    if (tasks.isEmpty) {
      return _controllers.length == 1 &&
          _taskIds.length == 1 &&
          _taskIds.first == null;
    }
    if (_controllers.length != tasks.length) return false;
    for (var i = 0; i < tasks.length; i++) {
      if (_taskIds[i] != tasks[i].id) return false;
      if (_done[i] != tasks[i].isDone) return false;
      if (_controllers[i].text != tasks[i].title) return false;
    }
    return true;
  }

  void _syncFromTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      _controllers.add(SpanTextEditingController(text: ''));
      _focusNodes.add(FocusNode());
      _taskIds.add(null);
      _done.add(false);
      _saveTimers.add(null);
      return;
    }
    for (final task in tasks) {
      _controllers.add(SpanTextEditingController(text: task.title));
      _focusNodes.add(FocusNode());
      _taskIds.add(task.id);
      _done.add(task.isDone);
      _saveTimers.add(null);
    }
  }

  void _disposeRows() {
    for (final timer in _saveTimers) {
      timer?.cancel();
    }
    for (final f in _focusNodes) {
      if (f.hasFocus) f.unfocus();
    }
    final controllers = List<SpanTextEditingController>.from(_controllers);
    final focusNodes = List<FocusNode>.from(_focusNodes);
    _controllers.clear();
    _focusNodes.clear();
    _taskIds.clear();
    _done.clear();
    _saveTimers.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers) {
        c.dispose();
      }
      for (final f in focusNodes) {
        f.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final timer in _saveTimers) {
      timer?.cancel();
    }
    _disposeRows();
    super.dispose();
  }

  Task? _taskById(int id) {
    for (final t in _displayTasks) {
      if (t.id == id) return t;
    }
    for (final t in widget.embed.tasks ?? const <Task>[]) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _applyPendingFocus() {
    if (!mounted) return;
    final idx = _pendingFocusIndex;
    if (idx == null || idx < 0 || idx >= _focusNodes.length) return;
    _pendingFocusIndex = null;
    _focusNodes[idx].requestFocus();
    final controller = _controllers[idx];
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
  }

  Future<void> _ensureSeedTask() async {
    if (_ensuringSeed || widget.embed.taskListId == null) return;
    if ((widget.embed.tasks ?? const []).isNotEmpty) return;
    _ensuringSeed = true;
    try {
      final created = await widget.state.createTaskInList(
        widget.embed.taskListId!,
        title: '',
        notify: false,
      );
      if (!mounted) return;
      setState(() {
        if (_taskIds.isEmpty) {
          _controllers.add(SpanTextEditingController(text: ''));
          _focusNodes.add(FocusNode());
          _taskIds.add(created.id);
          _done.add(false);
          _saveTimers.add(null);
        } else {
          _taskIds[0] = created.id;
        }
      });
      widget.onRefresh();
      _pendingFocusIndex = 0;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyPendingFocus());
    } finally {
      _ensuringSeed = false;
    }
  }

  void _scheduleSave(int index) {
    if (index < 0 || index >= _saveTimers.length) return;
    _saveTimers[index]?.cancel();
    _saveTimers[index] = Timer(const Duration(milliseconds: 400), () {
      unawaited(_flushTitle(index));
    });
  }

  Future<void> _flushTitle(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _taskIds.length) return;
    final id = _taskIds[index];
    if (id == null) return;
    final task = _taskById(id);
    if (task == null) return;
    final title = _controllers[index].text;
    if (task.title == title) return;
    try {
      await widget.state.updateTaskTitle(task, title, notify: false);
    } catch (_) {}
  }

  Future<void> _handleEnter(int index) async {
    widget.onFocus?.call();
    await _flushTitle(index);
    final text = _controllers[index].text;
    if (text.trim().isEmpty) {
      widget.onExitBelow?.call(index);
      return;
    }
    // New rows are always Active — insert after this task if active, else
    // append to the active zone.
    await _insertAfter(index);
  }

  Future<void> _handleBackspace(int index) async {
    widget.onFocus?.call();
    if (_controllers[index].text.trim().isEmpty) {
      await _removeAt(index);
    }
  }

  Future<void> _insertAfter(int index) async {
    if (widget.embed.taskListId == null) return;
    final afterId = _done[index] ? null : _taskIds[index];
    final created = await widget.state.createTaskInList(
      widget.embed.taskListId!,
      title: '',
      afterTaskId: afterId,
      notify: false,
    );
    if (!mounted) return;
    final newIndex = _done[index] ? _activeCount : index + 1;
    setState(() {
      _optimistic = null;
      _controllers.insert(newIndex, SpanTextEditingController(text: ''));
      _focusNodes.insert(newIndex, FocusNode());
      _taskIds.insert(newIndex, created.id);
      _done.insert(newIndex, false);
      _saveTimers.insert(newIndex, null);
    });
    widget.onRefresh();
    _pendingFocusIndex = newIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());
  }

  Future<void> _removeAt(int index) async {
    if (_controllers.length <= 1) {
      widget.onExitBelow?.call(index);
      return;
    }
    final id = _taskIds[index];
    final removedFocus = _focusNodes[index];
    setState(() {
      _optimistic = null;
      _saveTimers.removeAt(index)?.cancel();
      _controllers.removeAt(index).dispose();
      _focusNodes.removeAt(index);
      _taskIds.removeAt(index);
      _done.removeAt(index);
    });
    if (id != null) {
      final task = _taskById(id);
      if (task != null) {
        await widget.state.deleteTask(task, notify: false);
      }
    }
    widget.onRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removedFocus.dispose();
      if (!mounted) return;
      final focusPrev = index > 0 ? index - 1 : 0;
      if (focusPrev < _focusNodes.length) {
        _focusNodes[focusPrev].requestFocus();
      }
    });
  }

  Future<void> _toggle(int index) async {
    final id = _taskIds[index];
    if (id == null) return;
    final task = _taskById(id);
    if (task == null) return;
    final targetDone = !_done[index];
    final zones = TaskZones.fromOrdered(_displayTasks);
    final next = zones.moved(
      taskId: id,
      targetDone: targetDone,
      indexInZone: targetDone ? zones.done.length : zones.active.length,
    );
    _applyOptimistic(next);
    await _persistMove(
      task: task,
      targetDone: targetDone,
      insertIndexInZone:
          targetDone ? zones.done.length : zones.active.length,
      snapshot: zones,
    );
  }

  void _applyOptimistic(TaskZones next) {
    final titles = {
      for (var i = 0; i < _taskIds.length; i++)
        if (_taskIds[i] != null) _taskIds[i]!: _controllers[i].text,
    };
    final focusId = () {
      final fi = _focusNodes.indexWhere((f) => f.hasFocus);
      if (fi < 0) return null;
      return _taskIds[fi];
    }();

    setState(() {
      _optimistic = [
        for (final t in next.all)
          t.copyWith(title: titles[t.id] ?? t.title),
      ];
      _disposeRows();
      _syncFromTasks(_optimistic!);
      // Restore typed titles
      for (var i = 0; i < _taskIds.length; i++) {
        final id = _taskIds[i];
        if (id != null && titles.containsKey(id)) {
          _controllers[i].text = titles[id]!;
        }
      }
    });
    if (focusId != null) {
      final idx = _taskIds.indexOf(focusId);
      if (idx >= 0) {
        _pendingFocusIndex = idx;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _applyPendingFocus());
      }
    }
  }

  Future<void> _persistMove({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
    required TaskZones snapshot,
  }) async {
    _persisting = true;
    try {
      await widget.state.moveTaskInListZone(
        task: task,
        targetDone: targetDone,
        insertIndexInZone: insertIndexInZone,
        notify: false,
      );
      if (!mounted) return;
      // Keep optimistic until refresh brings matching order.
      widget.onRefresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _optimistic = null;
        _disposeRows();
        _syncFromTasks(snapshot.all);
      });
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(widget.state.strings['reorderFailed'])),
        );
      }
    } finally {
      _persisting = false;
    }
  }

  Future<void> _persistReorder(TaskZones next, TaskZones snapshot) async {
    if (widget.embed.taskListId == null) return;
    _persisting = true;
    try {
      await widget.state.reorderTasksInList(
        widget.embed.taskListId!,
        next.orderedIds,
        notify: false,
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _optimistic = null;
        _disposeRows();
        _syncFromTasks(snapshot.all);
      });
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(widget.state.strings['reorderFailed'])),
        );
      }
    } finally {
      _persisting = false;
    }
  }

  void _onDrop({
    required TaskDragPayload payload,
    required bool targetDone,
    required int indexInZone,
  }) {
    final listId = widget.embed.taskListId;
    if (listId == null || payload.sourceListId != listId) return;
    final zones = TaskZones.fromOrdered(_displayTasks);
    final next = zones.moved(
      taskId: payload.task.id,
      targetDone: targetDone,
      indexInZone: indexInZone,
    );
    if (next.orderedIds.join() == zones.orderedIds.join() &&
        payload.sourceDone == targetDone) {
      return;
    }
    _applyOptimistic(next);
    final task = payload.task;
    if (payload.sourceDone != targetDone) {
      unawaited(_persistMove(
        task: task,
        targetDone: targetDone,
        insertIndexInZone: indexInZone,
        snapshot: zones,
      ));
    } else {
      unawaited(_persistReorder(next, zones));
    }
  }

  Future<void> _showTextMenu(TapDownDetails details) async {
    await DocumentContextMenu.showTextMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      onAction: runBlockTextAction,
    );
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

  Widget _dropGap({
    required bool targetDone,
    required int indexInZone,
  }) {
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.sourceListId == widget.embed.taskListId,
      onAcceptWithDetails: (d) => _onDrop(
        payload: d.data,
        targetDone: targetDone,
        indexInZone: indexInZone,
      ),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: hot ? 10 : 2,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: hot
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }

  Widget _taskRow(int index) {
    final id = _taskIds[index];
    final task = id == null ? null : _taskById(id);
    final listId = widget.embed.taskListId;
    final mark = TaskMark(
      done: _done[index],
      compact: true,
      onToggle: () => unawaited(_toggle(index)),
    );

    final gutter = (task != null && listId != null)
        ? LongPressDraggable<TaskDragPayload>(
            data: TaskDragPayload(
              task: task,
              sourceListId: listId,
              sourceDone: _done[index],
            ),
            feedback: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  _controllers[index].text.trim().isEmpty
                      ? widget.state.strings['newTaskHint']
                      : _controllers[index].text,
                  style: AppTypography.documentParagraphStyle,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: mark),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: mark,
            ),
          )
        : mark;

    final zoneIndex = _done[index]
        ? index - _activeCount
        : index;

    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.sourceListId == widget.embed.taskListId,
      onAcceptWithDetails: (d) => _onDrop(
        payload: d.data,
        targetDone: _done[index],
        indexInZone: zoneIndex,
      ),
      builder: (context, candidate, rejected) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (candidate.isNotEmpty)
              Container(
                height: 2,
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: gutter,
                    ),
                  ),
                  Expanded(
                    child: FormattedTextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      segmentId: taskItemSegmentId(widget.blockId, index),
                      style: AppTypography.documentParagraphStyle.copyWith(
                        decoration:
                            _done[index] ? TextDecoration.lineThrough : null,
                        color: _done[index] ? AppColors.textHint : null,
                      ),
                      hintText: widget.state.strings['newTaskHint'],
                      maxLines: null,
                      minLines: 1,
                      onChanged: (_) {
                        widget.onFocus?.call();
                        _scheduleSave(index);
                      },
                      onEnter: () => unawaited(_handleEnter(index)),
                      onBackspaceAtStart: () => _handleBackspace(index),
                      onSecondaryTapDown: _showTextMenu,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeCount;
    final doneCount = _controllers.length - activeCount;
    final showDoneHeader = doneCount > 0;
    final s = widget.state.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDoneHeader) _zoneLabel(s['tasksActive']),
        for (var i = 0; i < activeCount; i++) _taskRow(i),
        _dropGap(targetDone: false, indexInZone: activeCount),
        if (showDoneHeader) ...[
          _zoneLabel(s['tasksDone']),
          for (var i = activeCount; i < _controllers.length; i++) _taskRow(i),
          _dropGap(targetDone: true, indexInZone: doneCount),
        ],
      ],
    );
  }
}
