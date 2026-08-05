import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../files/rich_text/block_text_actions.dart';
import '../../files/rich_text/document_context_menu.dart';
import '../../files/rich_text/formatted_text_field.dart';
import '../../files/rich_text/span_text_editing_controller.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../views/assign_task_view_dialog.dart';
import './task_drag_data.dart';
import './task_list_bridge.dart';
import './task_mark.dart';
import './task_zones.dart';

/// Drop of a task that belongs to the same drag group but not this surface
/// (e.g. another view frame).
typedef TaskListForeignDrop = void Function({
  required TaskDragPayload payload,
  required bool targetDone,
  required int indexInZone,
});

/// Local-row task list engine shared by in-file embeds and view frames.
///
/// Mutates controllers / optimistic order **before** awaiting the bridge API,
/// matching the in-file interaction model.
class TaskListSurface extends StatefulWidget {
  const TaskListSurface({
    super.key,
    required this.state,
    required this.bridge,
    this.onFocus,
    this.onExitBelow,
    this.compactMode = false,
    this.listTitleSegmentId,
    this.taskSegmentId,
    this.extraMenuEntries,
    this.onExtraMenuAction,
    this.onForeignDrop,
    this.onReorderModeChanged,
    this.climbToListTitleOnLastBackspace = true,
    this.includeAssignView = true,
  });

  final AppState state;
  final TaskListBridge bridge;
  final VoidCallback? onFocus;
  final ValueChanged<int?>? onExitBelow;
  final bool compactMode;
  final String? listTitleSegmentId;
  final String Function(int index)? taskSegmentId;
  final List<AppContextMenuEntry> Function(Task task)? extraMenuEntries;
  final Future<void> Function(String action, Task task)? onExtraMenuAction;
  final TaskListForeignDrop? onForeignDrop;
  final ValueChanged<bool>? onReorderModeChanged;
  final bool climbToListTitleOnLastBackspace;
  /// When false, the host supplies its own Choose view entry (view frames).
  final bool includeAssignView;

  @override
  State<TaskListSurface> createState() => TaskListSurfaceState();
}

class TaskListSurfaceState extends State<TaskListSurface> {
  late SpanTextEditingController _titleController;
  late final FocusNode _titleFocus;
  Timer? _titleSaveTimer;
  final _controllers = <SpanTextEditingController>[];
  final _focusNodes = <FocusNode>[];
  final _taskIds = <int?>[];
  final _done = <bool>[];
  final _saveTimers = <Timer?>[];
  int? _pendingFocusIndex;
  var _ensuringSeed = false;
  var _persisting = false;
  var _reorderMode = false;
  List<Task>? _optimistic;

  TaskListBridge get _bridge => widget.bridge;

  List<Task> get _remoteTasks => TaskZones.fromTasks(_bridge.remoteTasks).all;

  List<Task> get _displayTasks => _optimistic ?? _remoteTasks;

  int get _activeCount => _done.where((d) => !d).length;

  bool get reorderMode => _reorderMode;

  void setReorderMode(bool value) => _setReorderMode(value);

  @override
  void initState() {
    super.initState();
    _titleFocus = FocusNode();
    _titleController = SpanTextEditingController(text: _bridge.listTitle);
    _syncFromTasks(_displayTasks);
    if (_taskIds.isEmpty || _taskIds.every((id) => id == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureSeedTask());
      });
    }
  }

  @override
  void didUpdateWidget(TaskListSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_persisting) return;
    if (!_titleFocus.hasFocus &&
        oldWidget.bridge.listTitle != _bridge.listTitle) {
      _titleController.text = _bridge.listTitle;
    }
    if (_optimistic != null) {
      if (_idsMatch(_optimistic!, _remoteTasks)) {
        _optimistic = null;
      } else {
        return;
      }
    }
    if (_localMatchesRemote()) return;
    if (_focusNodes.any((f) => f.hasFocus) ||
        HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      return;
    }
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

  List<Task> _tasksFromLocalRows() {
    final out = <Task>[];
    for (var i = 0; i < _taskIds.length; i++) {
      final id = _taskIds[i];
      if (id == null) continue;
      final remote = _taskById(id);
      out.add(
        (remote ??
                Task(
                  id: id,
                  title: _controllers[i].text,
                  status: _done[i] ? 'done' : 'active',
                  listOrderIndex: i,
                ))
            .copyWith(
          title: _controllers[i].text,
          status: _done[i] ? 'done' : 'active',
          listOrderIndex: i,
        ),
      );
    }
    return out;
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
    _titleSaveTimer?.cancel();
    unawaited(_flushTitleHeader().catchError((_) {}));
    for (final timer in _saveTimers) {
      timer?.cancel();
    }
    _titleFocus.dispose();
    _titleController.dispose();
    _disposeRows();
    super.dispose();
  }

  void _scheduleTitleSave() {
    widget.onFocus?.call();
    _titleSaveTimer?.cancel();
    _titleSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_flushTitleHeader());
    });
  }

  Future<void> _flushTitleHeader() async {
    _titleSaveTimer?.cancel();
    if (!_bridge.showListTitle) return;
    final title = _titleController.text;
    if (title == _bridge.listTitle) return;
    try {
      await _bridge.updateListTitle(title);
    } catch (_) {}
  }

  void _onTitleEnter() {
    widget.onFocus?.call();
    unawaited(_flushTitleHeader());
    if (_focusNodes.isEmpty) return;
    _pendingFocusIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());
  }

  Task? _taskById(int id) {
    for (final t in _displayTasks) {
      if (t.id == id) return t;
    }
    for (final t in _bridge.remoteTasks) {
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
    if (_ensuringSeed) return;
    if (_bridge.remoteTasks.isNotEmpty) return;
    _ensuringSeed = true;
    try {
      final created = await _bridge.ensureSeed();
      if (!mounted) return;
      if (created == null) return;
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
        _optimistic = _tasksFromLocalRows();
      });
      await _bridge.refresh();
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
    if (_taskIds[index] == null) {
      await _persistUnsavedRow(index);
      return;
    }
    final id = _taskIds[index]!;
    final task = _taskById(id);
    if (task == null) return;
    final title = _controllers[index].text;
    if (task.title == title) return;
    try {
      await _bridge.updateTitle(task, title);
    } catch (_) {}
  }

  /// Create a server row for a local null-id seed once the user has typed.
  Future<void> _persistUnsavedRow(int index) async {
    if (_persisting) return;
    if (index < 0 || index >= _taskIds.length) return;
    if (_taskIds[index] != null) return;
    final title = _controllers[index].text;
    if (title.trim().isEmpty) return;
    _persisting = true;
    try {
      final created = await _bridge.createAfter(
        title: title,
        status: _done[index] ? 'done' : 'active',
        afterTaskId: index > 0 ? _taskIds[index - 1] : null,
      );
      if (!mounted) return;
      setState(() {
        _taskIds[index] = created.id;
        _optimistic = _tasksFromLocalRows();
      });
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _handleEnter(int index) async {
    widget.onFocus?.call();
    await _flushTitle(index);
    if (!mounted) return;
    if (index < 0 || index >= _controllers.length) return;
    final text = _controllers[index].text;
    if (text.trim().isEmpty) {
      final emptyId = _taskIds[index];
      for (final f in _focusNodes) {
        if (f.hasFocus) f.unfocus();
      }
      widget.onExitBelow?.call(emptyId);
      return;
    }
    await _insertAfter(index);
  }

  Future<void> _handleBackspace(int index) async {
    widget.onFocus?.call();
    if (_controllers[index].text.trim().isEmpty) {
      if (_controllers.length <= 1) {
        if (widget.climbToListTitleOnLastBackspace && _bridge.showListTitle) {
          _titleFocus.requestFocus();
          final len = _titleController.text.length;
          _titleController.selection =
              TextSelection.collapsed(offset: len);
          return;
        }
        widget.onExitBelow?.call(_taskIds[index]);
        return;
      }
      await _removeAt(index);
    }
  }

  Future<void> _insertAfter(int index) async {
    if (index < 0 || index >= _taskIds.length) return;
    if (_taskIds[index] == null) {
      await _persistUnsavedRow(index);
      if (!mounted || _taskIds[index] == null) return;
    }
    final asDone = _done[index];
    final afterId = _taskIds[index];
    final newIndex = index + 1;

    _persisting = true;
    setState(() {
      _controllers.insert(newIndex, SpanTextEditingController(text: ''));
      _focusNodes.insert(newIndex, FocusNode());
      _taskIds.insert(newIndex, null);
      _done.insert(newIndex, asDone);
      _saveTimers.insert(newIndex, null);
    });
    _pendingFocusIndex = newIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());

    try {
      final created = await _bridge.createAfter(
        title: '',
        afterTaskId: afterId,
        status: asDone ? 'done' : 'active',
      );
      if (!mounted) return;
      if (newIndex < _taskIds.length) {
        setState(() {
          _taskIds[newIndex] = created.id;
          _optimistic = _tasksFromLocalRows();
        });
      }
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _removeAt(int index) async {
    if (_controllers.length <= 1) {
      widget.onExitBelow?.call(_taskIds[index]);
      return;
    }
    final id = _taskIds[index];
    final known = id == null ? null : _taskById(id);
    if (known != null) {
      final ok = await _bridge.confirmDelete(known);
      if (!ok || !mounted) return;
    }
    final removedFocus = _focusNodes[index];
    final removedController = _controllers[index];

    _persisting = true;
    setState(() {
      _saveTimers.removeAt(index)?.cancel();
      _controllers.removeAt(index);
      _focusNodes.removeAt(index);
      _taskIds.removeAt(index);
      _done.removeAt(index);
      _optimistic = _tasksFromLocalRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removedController.dispose();
      removedFocus.dispose();
    });

    try {
      if (id != null) {
        await _bridge.delete(
          known ??
              Task(
                id: id,
                title: '',
                status: 'active',
              ),
        );
      }
      if (!mounted) return;
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
    if (!mounted) return;
    final focusPrev = index > 0 ? index - 1 : 0;
    if (focusPrev < _focusNodes.length) {
      _pendingFocusIndex = focusPrev;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyPendingFocus());
    }
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
      await _bridge.moveInZone(
        task: task,
        targetDone: targetDone,
        insertIndexInZone: insertIndexInZone,
      );
      if (!mounted) return;
      await _bridge.refresh();
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
    _persisting = true;
    try {
      await _bridge.reorder(next.orderedIds);
      if (!mounted) return;
      await _bridge.refresh();
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
    if (!_bridge.acceptsDrag(payload)) return;
    final localIds = {for (final id in _taskIds) ?id};
    if (!localIds.contains(payload.task.id)) {
      widget.onForeignDrop?.call(
        payload: payload,
        targetDone: targetDone,
        indexInZone: indexInZone,
      );
      return;
    }
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

  void _setReorderMode(bool value) {
    if (_reorderMode == value) return;
    setState(() => _reorderMode = value);
    widget.onReorderModeChanged?.call(value);
    if (value) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _showTaskMenu(TapDownDetails details, int index) async {
    final id = index >= 0 && index < _taskIds.length ? _taskIds[index] : null;
    final task = id == null ? null : _taskById(id);
    final extras = task == null
        ? const <AppContextMenuEntry>[]
        : (widget.extraMenuEntries?.call(task) ?? const []);

    await DocumentContextMenu.showTaskListMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      extraEntries: extras,
      includeAssignView: widget.includeAssignView,
      onAction: (action) async {
        if (action == 'tasks:reorder_mode') {
          _setReorderMode(true);
          return;
        }
        if (action == 'tasks:assign_view') {
          if (id == null || !mounted) return;
          await showAssignTaskViewDialog(
            context: context,
            state: widget.state,
            taskId: id,
          );
          return;
        }
        if (action == 'delete' && index >= 0) {
          await _removeAt(index);
          return;
        }
        if (task != null && widget.onExtraMenuAction != null) {
          await widget.onExtraMenuAction!(action, task);
          if (action.startsWith('list:') ||
              action.startsWith('section:') ||
              action.startsWith('topic:') ||
              action.startsWith('view:')) {
            return;
          }
        }
        await runBlockTextAction(action);
      },
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
    if (!_reorderMode) return const SizedBox(height: 2);
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (d) => _bridge.acceptsDrag(d.data),
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

  Widget _taskChrome({
    required Widget mark,
    required Widget title,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: mark,
          ),
          Expanded(child: title),
        ],
      ),
    );
  }

  Widget _compactTaskChip(int index, {required bool glass}) {
    final titleStyle = AppTypography.taskRowStyle.copyWith(
      decoration: _done[index] ? TextDecoration.lineThrough : null,
      color: _done[index] ? AppColors.textHint : null,
    );
    final titleText = _controllers[index].text.trim().isEmpty
        ? widget.state.strings['newTaskHint']
        : _controllers[index].text;
    final mark = TaskMark(
      done: _done[index],
      compact: true,
      onToggle: () {},
    );
    final maxChipWidth = MediaQuery.sizeOf(context).width * 0.72;
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxChipWidth - 52),
          child: Text(titleText, style: titleStyle),
        ),
      ],
    );
    final chip = glass ? DragModeFrame.chip(child: body) : body;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: chip,
    );
  }

  Widget _taskRow(int index) {
    if (index < 0 || index >= _controllers.length) {
      return const SizedBox.shrink();
    }
    final id = _taskIds[index];
    final task = id == null ? null : _taskById(id);
    final groupId = _bridge.dragGroupId;
    final zoneIndex = _done[index] ? index - _activeCount : index;

    if (widget.compactMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _compactTaskChip(index, glass: false),
      );
    }

    if (_reorderMode) {
      final framed = _compactTaskChip(index, glass: true);
      if (task == null) return framed;
      return DragTarget<TaskDragPayload>(
        onWillAcceptWithDetails: (d) => _bridge.acceptsDrag(d.data),
        onAcceptWithDetails: (d) => _onDrop(
          payload: d.data,
          targetDone: _done[index],
          indexInZone: zoneIndex,
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
                  sourceListId: groupId,
                  sourceDone: _done[index],
                ),
                feedback: Material(
                  color: Colors.transparent,
                  child: _compactTaskChip(index, glass: true),
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

    final titleStyle = AppTypography.taskRowStyle.copyWith(
      decoration: _done[index] ? TextDecoration.lineThrough : null,
      color: _done[index] ? AppColors.textHint : null,
    );
    final mark = TaskMark(
      done: _done[index],
      compact: true,
      onToggle: () => unawaited(_toggle(index)),
    );

    return _taskChrome(
      mark: mark,
      title: FormattedTextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        segmentId: widget.taskSegmentId?.call(index),
        style: titleStyle,
        hintText: widget.state.strings['newTaskHint'],
        maxLines: null,
        minLines: 1,
        textAlignVertical: TextAlignVertical.center,
        onChanged: (_) {
          widget.onFocus?.call();
          _scheduleSave(index);
        },
        onEnter: () => unawaited(_handleEnter(index)),
        onBackspaceAtStart: () => _handleBackspace(index),
        onSecondaryTapDown: (d) => _showTaskMenu(d, index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeCount;
    final doneCount = _controllers.length - activeCount;
    final showDoneHeader = doneCount > 0;
    final s = widget.state.strings;
    final compact = widget.compactMode;

    final list = Column(
      crossAxisAlignment:
          compact || _reorderMode ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
      children: [
        if (_bridge.showListTitle && !compact && !_reorderMode)
          FormattedTextField(
            controller: _titleController,
            focusNode: _titleFocus,
            segmentId: widget.listTitleSegmentId,
            style: AppTypography.noteTitleStyle,
            hintText: s['taskListTitleHint'],
            maxLines: 1,
            minLines: 1,
            onChanged: (_) => _scheduleTitleSave(),
            onEnter: _onTitleEnter,
            onSecondaryTapDown: (d) => unawaited(
              DocumentContextMenu.showTextMenu(
                context: context,
                globalPosition: d.globalPosition,
                strings: widget.state.strings,
                onAction: runBlockTextAction,
              ),
            ),
          ),
        if (_bridge.showListTitle && !compact && !_reorderMode)
          const SizedBox(height: 4),
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

    if (!_reorderMode) return list;

    return TapRegion(
      onTapOutside: (_) => _setReorderMode(false),
      child: list,
    );
  }
}
