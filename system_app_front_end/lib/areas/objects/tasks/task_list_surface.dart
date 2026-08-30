import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/editor/document_mark.dart';
import '../../files/editor/document_text_flow.dart';
import '../../files/editor/drag_mode_frame.dart';
import '../../files/editor/editor_key_handoff.dart';
import '../../files/editor/embed_caret_bridge.dart';
import '../../files/rich_text/block_text_actions.dart';
import '../../files/rich_text/block_text_focus.dart';
import '../../files/rich_text/connect_info.dart';
import '../../files/rich_text/document_context_menu.dart';
import '../../files/rich_text/formatted_text_field.dart';
import '../../files/rich_text/list_text_parse.dart';
import '../../files/rich_text/span_text_editing_controller.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/object_embed.dart';
import '../data/task.dart';
import '../../automations/automation.dart';
import '../../automations/complimentary_input_dialog.dart';
import '../../production_agent/pending_review_ui.dart';
import '../views/assign_task_view_dialog.dart';
import './task_drag_data.dart';
import './task_list_bridge.dart';
import './task_mark.dart';
import './task_zones.dart';

/// Drop of a task that belongs to the same drag group but not this surface
/// (e.g. another view frame).
typedef TaskListForeignDrop =
    void Function({
      required TaskDragPayload payload,
      required bool targetDone,
      required int indexInZone,
    });

/// Keep typed/pasted text instead of a stale refresh (empty create payload).
bool keepLocalTaskTitle({
  required String local,
  required String incoming,
  required bool focused,
  required bool savePending,
}) {
  final localText = imeVisibleText(local);
  final incomingText = imeVisibleText(incoming);
  if (localText == incomingText) return true;
  if (focused) return true;
  if (savePending) return true;
  if (localText.isNotEmpty && incomingText.isEmpty) return true;
  return false;
}

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
    this.onDeleteObject,
    this.compactMode = false,
    this.listTitleSegmentId,
    this.documentBaseOffset = 0,
    this.extraMenuEntries,
    this.onExtraMenuAction,
    this.onForeignDrop,
    this.onReorderModeChanged,
    this.climbToListTitleOnLastBackspace = true,
    this.includeAssignView = true,
    this.onArrowExitAbove,
    this.onArrowExitBelow,
    this.hostEmbed,
  });

  final AppState state;
  final TaskListBridge bridge;
  final VoidCallback? onFocus;
  final ValueChanged<int?>? onExitBelow;

  /// Last empty task + Backspace when the list should leave the file (in-file
  /// host). Views leave this null and keep the empty seed row.
  final VoidCallback? onDeleteObject;
  final bool compactMode;
  final String? listTitleSegmentId;

  /// Start of the host pointer/part in the marker-text buffer (in-file only).
  final int documentBaseOffset;
  final List<AppContextMenuEntry> Function(Task task)? extraMenuEntries;
  final Future<void> Function(String action, Task task)? onExtraMenuAction;
  final TaskListForeignDrop? onForeignDrop;
  final ValueChanged<bool>? onReorderModeChanged;
  final bool climbToListTitleOnLastBackspace;

  /// When false, the host supplies its own Choose view entry (view frames).
  final bool includeAssignView;

  /// ↑ on the first line of the list — leave the embed upward.
  final VoidCallback? onArrowExitAbove;

  /// ↓ on the last line of the list — leave the embed downward.
  final VoidCallback? onArrowExitBelow;

  /// In-file host object — list title Connect info still stores on this object.
  final ObjectEmbed? hostEmbed;

  @override
  State<TaskListSurface> createState() => TaskListSurfaceState();
}

class TaskListSurfaceState extends State<TaskListSurface> {
  /// List whose field currently owns the caret — for the reorder-mode shortcut.
  static TaskListSurfaceState? keyboardFocus;

  late SpanTextEditingController _titleController;
  late final FocusNode _titleFocus;
  Timer? _titleSaveTimer;
  final _controllers = <SpanTextEditingController>[];
  final _focusNodes = <FocusNode>[];
  final _taskIds = <int?>[];
  final _done = <bool>[];
  final _saveTimers = <Timer?>[];
  final _rowKeys = <Object>[];
  int? _pendingFocusIndex;
  int? _pasteTargetIndex;
  var _ensuringSeed = false;
  var _persisting = false;
  var _reorderMode = false;
  int? _reorderResumeIndex;
  List<Task>? _optimistic;
  final _flow = DocumentTextFlow();

  TaskListBridge get _bridge => widget.bridge;

  List<Task> get _remoteTasks => _bridge.sortRemoteByListOrder
      ? TaskZones.fromTasks(_bridge.remoteTasks).all
      : TaskZones.fromOrdered(_bridge.remoteTasks).all;

  List<Task> get _displayTasks => _optimistic ?? _remoteTasks;

  int get _activeCount => _done.where((d) => !d).length;

  bool get reorderMode => _reorderMode;

  void setReorderMode(bool value) => _setReorderMode(value);

  void toggleReorderMode() => _setReorderMode(!_reorderMode);

  Future<void> connectInfoFromShortcut() async {
    if (_titleFocus.hasFocus) {
      await _connectInfo(segmentId: widget.listTitleSegmentId);
      return;
    }
    final index = _focusNodes.indexWhere((f) => f.hasFocus);
    if (index >= 0) await _connectTaskInfo(index);
  }

  bool get _hasTitleLine =>
      _bridge.showListTitle && !widget.compactMode && !_reorderMode;

  /// Title (optional) + each task row — document-order lines for ↑/↓.
  int get lineCount => (_hasTitleLine ? 1 : 0) + _controllers.length;

  /// Document caret entering this list from above.
  void focusFirstLine() => focusLine(0, fromAbove: true);

  /// Document caret entering this list from below.
  void focusLastLine() {
    if (lineCount <= 0) return;
    focusLine(lineCount - 1, fromAbove: false);
  }

  void focusLine(int index, {required bool fromAbove}) {
    if (lineCount <= 0) return;
    final i = index.clamp(0, lineCount - 1);
    if (_hasTitleLine && i == 0) {
      focusFieldLine(_titleFocus, _titleController, fromAbove: fromAbove);
      return;
    }
    final taskIndex = _hasTitleLine ? i - 1 : i;
    if (taskIndex < 0 || taskIndex >= _focusNodes.length) return;
    focusFieldLine(
      _focusNodes[taskIndex],
      _controllers[taskIndex],
      fromAbove: fromAbove,
    );
  }

  void nudge(AxisDirection direction) {
    final titleLine = _hasTitleLine && _titleFocus.hasFocus;
    final taskIndex = _focusNodes.indexWhere((f) => f.hasFocus);
    final line = titleLine
        ? 0
        : (taskIndex >= 0 ? taskIndex + (_hasTitleLine ? 1 : 0) : -1);
    if (line < 0) return;
    if (direction == AxisDirection.left || direction == AxisDirection.right) {
      return;
    }
    _arrowFromLine(line, goingDown: direction == AxisDirection.down);
  }

  void _arrowFromLine(int lineIndex, {required bool goingDown}) {
    if (goingDown) {
      if (lineIndex < lineCount - 1) {
        focusLine(lineIndex + 1, fromAbove: true);
        return;
      }
      widget.onArrowExitBelow?.call();
      return;
    }
    if (lineIndex > 0) {
      focusLine(lineIndex - 1, fromAbove: false);
      return;
    }
    widget.onArrowExitAbove?.call();
  }

  @override
  void initState() {
    super.initState();
    _titleFocus = FocusNode();
    _titleFocus.addListener(_onFieldFocus);
    _titleController = SpanTextEditingController(text: _bridge.listTitle);
    _syncFromTasks(_displayTasks);
    _syncFlowOrder();
    _flow.onPruneStructures = _onPruneFullyMarked;
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
      } else if (_optimistic!.isNotEmpty) {
        return;
      } else {
        // Empty optimistic (seed-only) must not block adopting real tasks.
        _optimistic = null;
      }
    }
    _syncRowsFromRemote();
  }

  /// Pull remote tasks into the row model. Drops the empty placeholder once
  /// a real task has landed in this list (new section + drag/Place).
  void syncFromRemote() {
    if (!mounted || _persisting) return;
    _optimistic = null;
    _syncRowsFromRemote(notify: true);
  }

  void _syncRowsFromRemote({bool notify = false}) {
    final tasks = _displayTasks;
    if (tasks.isNotEmpty) _dropBlankUnsavedSeeds();
    if (!_rowsNeedAdopt(tasks)) {
      if (notify && mounted) setState(() {});
      return;
    }
    _adoptTasks(tasks);
    if (notify && mounted) setState(() {});
  }

  bool _idsMatch(List<Task> a, List<Task> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].isDone != b[i].isDone) return false;
    }
    return true;
  }

  bool _rowsNeedAdopt(List<Task> tasks) {
    if (tasks.isEmpty) {
      return !(_controllers.length == 1 &&
          _taskIds.length == 1 &&
          _taskIds.first == null);
    }
    // A leftover empty seed must not sit next to real tasks.
    if (_taskIds.any((id) => id == null)) return true;
    if (_taskIds.whereType<int>().length != tasks.length) return true;
    if (_taskIds.length != tasks.length) return true;
    for (var i = 0; i < tasks.length; i++) {
      if (_taskIds[i] != tasks[i].id) return true;
      if (_done[i] != tasks[i].isDone) return true;
      final focused = i < _focusNodes.length && _focusNodes[i].hasFocus;
      if (!focused && imeVisibleText(_controllers[i].text) != tasks[i].title) {
        return true;
      }
    }
    return false;
  }

  /// Unsaved empty placeholder — shown only while the list has no real tasks.
  bool _isBlankUnsavedRow(int index) {
    if (index < 0 || index >= _taskIds.length) return false;
    if (_taskIds[index] != null) return false;
    return imeFieldLooksEmpty(_controllers[index].text);
  }

  bool _dropBlankUnsavedSeeds() {
    final removedControllers = <SpanTextEditingController>[];
    final removedFocus = <FocusNode>[];
    for (var i = _taskIds.length - 1; i >= 0; i--) {
      if (!_isBlankUnsavedRow(i)) continue;
      _saveTimers.removeAt(i)?.cancel();
      removedControllers.add(_controllers.removeAt(i));
      removedFocus.add(_focusNodes.removeAt(i));
      _taskIds.removeAt(i);
      _done.removeAt(i);
      _rowKeys.removeAt(i);
    }
    if (removedControllers.isEmpty) return false;
    _syncFlowOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in removedControllers) {
        c.dispose();
      }
      for (final f in removedFocus) {
        f.dispose();
      }
    });
    return true;
  }

  /// Reuse controllers / focus nodes by [Task.id] so an insert is a new row
  /// and existing titles, carets, and links stay on their task.
  void _adoptTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      if (_controllers.length == 1 &&
          _taskIds.length == 1 &&
          _taskIds.first == null) {
        return;
      }
      final oldControllers = List<SpanTextEditingController>.from(_controllers);
      final oldFocus = List<FocusNode>.from(_focusNodes);
      final oldTimers = List<Timer?>.from(_saveTimers);
      _controllers.clear();
      _focusNodes.clear();
      _taskIds.clear();
      _done.clear();
      _saveTimers.clear();
      _rowKeys.clear();
      _syncFromTasks(const []);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final timer in oldTimers) {
          timer?.cancel();
        }
        for (final c in oldControllers) {
          c.dispose();
        }
        for (final f in oldFocus) {
          f.dispose();
        }
      });
      return;
    }

    final oldControllers = List<SpanTextEditingController>.from(_controllers);
    final oldFocus = List<FocusNode>.from(_focusNodes);
    final oldIds = List<int?>.from(_taskIds);
    final oldTimers = List<Timer?>.from(_saveTimers);
    final oldRowKeys = List<Object>.from(_rowKeys);
    final byId = <int, int>{};
    for (var i = 0; i < oldIds.length; i++) {
      final id = oldIds[i];
      if (id != null) byId[id] = i;
    }

    final nextControllers = <SpanTextEditingController>[];
    final nextFocus = <FocusNode>[];
    final nextIds = <int?>[];
    final nextDone = <bool>[];
    final nextTimers = <Timer?>[];
    final nextRowKeys = <Object>[];

    for (final task in tasks) {
      final oldIndex = byId[task.id];
      if (oldIndex != null) {
        final focus = oldFocus[oldIndex];
        final controller = oldControllers[oldIndex];
        final pending = oldTimers[oldIndex]?.isActive ?? false;
        if (!keepLocalTaskTitle(
              local: controller.text,
              incoming: task.title,
              focused: focus.hasFocus,
              savePending: pending,
            ) &&
            imeVisibleText(controller.text) != task.title) {
          controller.text = task.title;
        }
        nextControllers.add(controller);
        nextFocus.add(focus);
        nextIds.add(task.id);
        nextDone.add(task.isDone);
        nextTimers.add(oldTimers[oldIndex]);
        nextRowKeys.add(oldRowKeys[oldIndex]);
      } else {
        nextControllers.add(SpanTextEditingController(text: task.title));
        nextFocus.add(_createRowFocus());
        nextIds.add(task.id);
        nextDone.add(task.isDone);
        nextTimers.add(null);
        nextRowKeys.add(Object());
      }
    }

    final kept = {...nextControllers};
    _controllers
      ..clear()
      ..addAll(nextControllers);
    _focusNodes
      ..clear()
      ..addAll(nextFocus);
    _taskIds
      ..clear()
      ..addAll(nextIds);
    _done
      ..clear()
      ..addAll(nextDone);
    _saveTimers
      ..clear()
      ..addAll(nextTimers);
    _rowKeys
      ..clear()
      ..addAll(nextRowKeys);
    _syncFlowOrder();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var i = 0; i < oldControllers.length; i++) {
        if (kept.contains(oldControllers[i])) continue;
        oldTimers[i]?.cancel();
        oldControllers[i].dispose();
        oldFocus[i].dispose();
      }
    });
  }

  void _syncFromTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      _controllers.add(SpanTextEditingController(text: ''));
      _focusNodes.add(_createRowFocus());
      _taskIds.add(null);
      _done.add(false);
      _saveTimers.add(null);
      _rowKeys.add(Object());
      _syncFlowOrder();
      return;
    }
    for (final task in tasks) {
      _controllers.add(SpanTextEditingController(text: task.title));
      _focusNodes.add(_createRowFocus());
      _taskIds.add(task.id);
      _done.add(task.isDone);
      _saveTimers.add(null);
      _rowKeys.add(Object());
    }
    _syncFlowOrder();
  }

  String? get _titleSegmentId => _hasTitleLine
      ? (widget.listTitleSegmentId ?? 'taskListTitle:local')
      : null;

  void _syncFlowOrder() {
    final ids = <String>[
      ?_titleSegmentId,
      for (var i = 0; i < _controllers.length; i++) _taskSegmentId(i),
    ];
    _flow.setOrder(ids);
  }

  /// Tasks Choose view / ⌘J should hit: every marked task in this list, else
  /// the focused task.
  List<int> markedTaskIds() {
    final fromMark = _taskIdsFromMark(BlockTextFocusRegistry.resolveMark());
    if (fromMark.isNotEmpty) return fromMark;
    final fromFlow = _taskIdsFromMark(DocumentMark.resolve(_flow));
    if (fromFlow.isNotEmpty) return fromFlow;
    final i = _focusNodes.indexWhere((f) => f.hasFocus);
    if (i >= 0) {
      final id = _taskIds[i];
      if (id != null) return [id];
    }
    return const [];
  }

  List<Task> markedTasks() {
    final ids = markedTaskIds();
    if (ids.isEmpty) return const [];
    final byId = {for (final t in _tasksFromLocalRows()) t.id: t};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Marked / focused tasks on the view page for Place… (⌘J).
  static List<Task> tasksForPlace(AppState state) {
    final fromSurface = keyboardFocus?.markedTasks() ?? const [];
    if (fromSurface.isNotEmpty) return fromSurface;
    return [
      for (final id in taskIdsForAssignView())
        if (state.tasksById[id] != null) state.tasksById[id]!,
    ];
  }

  /// Marked tasks in the list that currently owns the caret, else [fallback].
  static List<int> taskIdsForAssignView({int? fallback}) {
    final marked = keyboardFocus?.markedTaskIds() ?? const [];
    if (marked.isNotEmpty) return marked;
    if (fallback != null) return [fallback];
    final active =
        BlockTextFocusRegistry.activeTaskId ??
        DocumentEditorRegistry.active?.focusedTaskId?.call();
    if (active != null) return [active];
    return const [];
  }

  List<int> _taskIdsFromMark(DocumentMark mark) {
    final out = <int>[];
    final seen = <int>{};
    for (final span in mark.spans) {
      final id = _taskIdFromSegment(span.segmentId);
      if (id != null && seen.add(id)) out.add(id);
    }
    return out;
  }

  int? _taskIdFromSegment(String? segmentId) {
    if (segmentId == null) return null;
    final byId = parseTaskIdSegmentId(segmentId);
    if (byId != null) return byId;
    final parsed = parseTaskItemSegmentId(segmentId);
    if (parsed != null) {
      final i = parsed.$2;
      if (i >= 0 && i < _taskIds.length) return _taskIds[i];
    }
    return null;
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
                  title: imeVisibleText(_controllers[i].text),
                  status: _done[i] ? 'done' : 'active',
                  listOrderIndex: i,
                ))
            .copyWith(
              title: imeVisibleText(_controllers[i].text),
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
    _rowKeys.clear();
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
    if (identical(keyboardFocus, this)) keyboardFocus = null;
    if (identical(BlockTextFocusRegistry.pasteOverride, tryPasteAsTasks)) {
      BlockTextFocusRegistry.pasteOverride = null;
    }
    _titleSaveTimer?.cancel();
    unawaited(_flushTitleHeader().catchError((_) {}));
    for (final timer in _saveTimers) {
      timer?.cancel();
    }
    _titleFocus.removeListener(_onFieldFocus);
    _titleFocus.dispose();
    _titleController.dispose();
    _disposeRows();
    _flow.onPruneStructures = null;
    _flow.dispose();
    super.dispose();
  }

  bool get _anyFieldFocused =>
      _titleFocus.hasFocus || _focusNodes.any((f) => f.hasFocus);

  void _onFieldFocus() {
    if (_anyFieldFocused) {
      keyboardFocus = this;
      final taskIndex = _focusNodes.indexWhere((f) => f.hasFocus);
      if (taskIndex >= 0) _pasteTargetIndex = taskIndex;
      BlockTextFocusRegistry.pasteOverride =
          taskIndex >= 0 ? tryPasteAsTasks : null;
      return;
    }
    if (identical(BlockTextFocusRegistry.pasteOverride, tryPasteAsTasks)) {
      BlockTextFocusRegistry.pasteOverride = null;
    }
    if (_reorderMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_anyFieldFocused || _reorderMode) return;
      if (identical(keyboardFocus, this)) keyboardFocus = null;
    });
  }

  FocusNode _createRowFocus() {
    final node = FocusNode();
    node.addListener(_onFieldFocus);
    return node;
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
      if (t.id == id) return widget.state.hydrateTask(t);
    }
    for (final t in _bridge.remoteTasks) {
      if (t.id == id) return widget.state.hydrateTask(t);
    }
    return widget.state.taskById(id);
  }

  void _applyPendingFocus() {
    if (!mounted) return;
    final idx = _pendingFocusIndex;
    if (idx == null || idx < 0 || idx >= _focusNodes.length) return;
    _pendingFocusIndex = null;
    _focusNodes[idx].requestFocus();
    final controller = _controllers[idx];
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  Future<void> _ensureSeedTask() async {
    if (_ensuringSeed) return;
    if (_bridge.remoteTasks.isNotEmpty) return;
    if (_taskIds.any((id) => id != null)) return;
    _ensuringSeed = true;
    try {
      final created = await _bridge.ensureSeed();
      if (!mounted) return;
      if (created == null) return;
      setState(() {
        if (_taskIds.isEmpty) {
          _controllers.add(SpanTextEditingController(text: ''));
          _focusNodes.add(_createRowFocus());
          _taskIds.add(created.id);
          _done.add(false);
          _saveTimers.add(null);
          _rowKeys.add(Object());
        } else {
          _taskIds[0] = created.id;
        }
        _optimistic = _tasksFromLocalRows();
      });
      await _bridge.refresh();
      // Do not steal focus to the seed row — insert/enter lands on the list
      // header when present ([_hasTitleLine]).
      if (!_hasTitleLine) {
        _pendingFocusIndex = 0;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _applyPendingFocus(),
        );
      }
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
      if (_persisting) {
        _scheduleSave(index);
        return;
      }
      await _persistUnsavedRow(index);
      return;
    }
    final id = _taskIds[index]!;
    final title = imeVisibleText(_controllers[index].text);
    final task = _taskById(id);
    if (task == null) {
      _scheduleSave(index);
      return;
    }
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
    final title = imeVisibleText(_controllers[index].text);
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
    if (imeFieldLooksEmpty(text)) {
      final emptyId = _taskIds[index];
      // No sync unfocus mid-Enter — document handoff waits for KeyUp.
      widget.onExitBelow?.call(emptyId);
      return;
    }
    await _insertAfter(index);
  }

  /// Fully marked tasks (whole title) are removed, not left as empty rows.
  void _onPruneFullyMarked(
    Set<String> fullyEmptied, {
    required bool spansParts,
  }) {
    final indices = <int>[
      for (var i = 0; i < _controllers.length; i++)
        if (fullyEmptied.contains(_taskSegmentId(i))) i,
    ];
    if (indices.isEmpty) return;
    unawaited(_dropFullyMarkedTasks(indices));
  }

  Future<void> _dropFullyMarkedTasks(List<int> indices) async {
    if (indices.isEmpty || !mounted || _persisting) return;
    widget.onFocus?.call();
    final unique = indices.toSet().toList()..sort();
    final removingAll = unique.length >= _controllers.length;

    // Inner mark-delete must not destroy the object — keep one empty row.
    // Delete the object from chrome / empty Backspace on the last unit.
    var drop = unique;
    if (removingAll) {
      drop = unique.skip(1).toList();
    }
    if (drop.isEmpty) return;

    _persisting = true;
    final descending = [...drop]..sort((a, b) => b.compareTo(a));
    final toDelete = <Task>[];
    for (final i in drop) {
      final id = _taskIds[i];
      if (id == null) continue;
      final task = _taskById(id);
      if (task != null) toDelete.add(task);
    }

    final removedControllers = <SpanTextEditingController>[];
    final removedFocus = <FocusNode>[];

    void dropRows() {
      if (!mounted) return;
      _flow.clearSelection();
      setState(() {
        for (final i in descending) {
          if (i < 0 || i >= _controllers.length) continue;
          _saveTimers.removeAt(i)?.cancel();
          removedControllers.add(_controllers.removeAt(i));
          removedFocus.add(_focusNodes.removeAt(i));
          _taskIds.removeAt(i);
          _done.removeAt(i);
          _rowKeys.removeAt(i);
        }
        _optimistic = _tasksFromLocalRows();
      });
      _syncFlowOrder();
      final focusIndex = () {
        final firstDropped = drop.first;
        if (firstDropped > 0) return firstDropped - 1;
        return 0;
      }();
      if (focusIndex < _focusNodes.length) {
        _focusNodes[focusIndex].requestFocus();
        final controller = _controllers[focusIndex];
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
      }
    }

    if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      final ready = Completer<void>();
      runAfterKeystroke(() {
        dropRows();
        ready.complete();
      });
      await ready.future;
    } else {
      dropRows();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in removedControllers) {
        c.dispose();
      }
      for (final f in removedFocus) {
        f.dispose();
      }
    });

    try {
      for (final task in toDelete) {
        await _bridge.delete(task);
      }
      if (!mounted) return;
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _handleBackspace(int index) async {
    if (_persisting) return;
    widget.onFocus?.call();
    if (imeFieldLooksEmpty(_controllers[index].text)) {
      if (_controllers.length <= 1) {
        if (widget.climbToListTitleOnLastBackspace &&
            _bridge.showListTitle &&
            !imeFieldLooksEmpty(_titleController.text)) {
          _titleFocus.requestFocus();
          final len = _titleController.text.length;
          _titleController.selection = TextSelection.collapsed(offset: len);
          return;
        }
        // Last empty task: delete the object. Cascade removes the task row —
        // a prior DELETE /tasks/:id 404s because the object delete already
        // took it.
        if (widget.onDeleteObject != null) {
          if (!mounted) return;
          _persisting = true;
          runAfterKeystroke(() {
            if (!mounted) return;
            widget.onDeleteObject!();
          });
          return;
        }
        await _removeAt(index);
        return;
      }
      await _removeAt(index);
    }
  }

  /// Multi-line paste on a task title → one task per line.
  ///
  /// First line stays in the focused row (at the caret / replacing a mark).
  /// The rest are created after it. A mark that already spans several tasks
  /// keeps the default replace path.
  Future<bool> tryPasteAsTasks(String raw) async {
    final lines = parsePastedListText(raw);
    if (lines.length < 2) return false;
    var index = _focusNodes.indexWhere((f) => f.hasFocus);
    if (index < 0) index = _pasteTargetIndex ?? -1;
    if (index < 0 || index >= _controllers.length) return false;
    final mark = BlockTextFocusRegistry.resolveMark();
    if (mark.fromMarking && mark.spansParts) return false;

    widget.onFocus?.call();
    if (mark.fromMarking) {
      mark.replaceWith(lines.first);
    } else {
      BlockTextFocusRegistry.insertText(lines.first);
    }
    _scheduleSave(index);
    await _insertTasksAfter(index, lines.sublist(1));
    return true;
  }

  Future<void> _insertTasksAfter(int index, List<String> titles) async {
    if (titles.isEmpty) return;
    if (index < 0 || index >= _taskIds.length) return;
    if (_taskIds[index] == null) {
      await _persistUnsavedRow(index);
      if (!mounted || _taskIds[index] == null) return;
    }
    final asDone = _done[index];
    var afterId = _taskIds[index];
    final start = index + 1;

    _persisting = true;
    setState(() {
      for (var i = 0; i < titles.length; i++) {
        final at = start + i;
        _controllers.insert(at, SpanTextEditingController(text: titles[i]));
        _focusNodes.insert(at, _createRowFocus());
        _taskIds.insert(at, null);
        _done.insert(at, asDone);
        _saveTimers.insert(at, null);
        _rowKeys.insert(at, Object());
      }
      _optimistic = _tasksFromLocalRows();
    });
    _syncFlowOrder();
    _pendingFocusIndex = start + titles.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());

    try {
      for (var i = 0; i < titles.length; i++) {
        final at = start + i;
        final created = await _bridge.createAfter(
          title: titles[i],
          afterTaskId: afterId,
          status: asDone ? 'done' : 'active',
        );
        if (!mounted) return;
        if (at < _taskIds.length) {
          setState(() {
            _taskIds[at] = created.id;
            _optimistic = _tasksFromLocalRows();
          });
        }
        afterId = created.id;
      }
      if (!mounted) return;
      await _bridge.refresh();
    } finally {
      _persisting = false;
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
      _focusNodes.insert(newIndex, _createRowFocus());
      _taskIds.insert(newIndex, null);
      _done.insert(newIndex, asDone);
      _saveTimers.insert(newIndex, null);
      _rowKeys.insert(newIndex, Object());
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
        await _flushTitle(newIndex);
      }
      if (!mounted) return;
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _removeAt(int index) async {
    if (_persisting) return;
    if (_controllers.length <= 1) {
      widget.onExitBelow?.call(_taskIds[index]);
      return;
    }
    final id = _taskIds[index];
    final known = id == null ? null : _taskById(id);
    _persisting = true;
    try {
      if (known != null) {
        final ok = await _bridge.confirmDelete(known);
        if (!ok || !mounted) return;
      }
      if (index < 0 || index >= _controllers.length) return;
      final removedFocus = _focusNodes[index];
      final removedController = _controllers[index];

      void dropRow() {
        if (!mounted) return;
        _flow.clearSelection();
        setState(() {
          _saveTimers.removeAt(index)?.cancel();
          _controllers.removeAt(index);
          _focusNodes.removeAt(index);
          _taskIds.removeAt(index);
          _done.removeAt(index);
          _rowKeys.removeAt(index);
          _optimistic = _tasksFromLocalRows();
        });
        _syncFlowOrder();
        final nextFocus = index > 0 ? index - 1 : 0;
        if (nextFocus < _focusNodes.length) {
          _focusNodes[nextFocus].requestFocus();
          final controller = _controllers[nextFocus];
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        }
      }

      if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
        final ready = Completer<void>();
        runAfterKeystroke(() {
          dropRow();
          ready.complete();
        });
        await ready.future;
      } else {
        dropRow();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        removedController.dispose();
        removedFocus.dispose();
      });

      if (id != null) {
        await _bridge.delete(
          known ?? Task(id: id, title: '', status: 'active'),
        );
      }
      if (!mounted) return;
      await _bridge.refresh();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _toggle(int index) async {
    final id = _taskIds[index];
    if (id == null) return;
    final task = _taskById(id);
    if (task == null || task.isComplimentaryTask) return;
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
      insertIndexInZone: targetDone ? zones.done.length : zones.active.length,
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
        for (final t in next.all) t.copyWith(title: titles[t.id] ?? t.title),
      ];
      _adoptTasks(_optimistic!);
    });
    if (focusId != null) {
      final idx = _taskIds.indexOf(focusId);
      if (idx >= 0) {
        _pendingFocusIndex = idx;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _applyPendingFocus(),
        );
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
      if (_dropBlankUnsavedSeeds()) setState(() {});
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
      unawaited(
        _persistMove(
          task: task,
          targetDone: targetDone,
          insertIndexInZone: indexInZone,
          snapshot: zones,
        ),
      );
    } else {
      unawaited(_persistReorder(next, zones));
    }
  }

  void _setReorderMode(bool value) {
    if (_reorderMode == value) return;
    if (value) {
      keyboardFocus = this;
      final fi = _focusNodes.indexWhere((f) => f.hasFocus);
      _reorderResumeIndex = fi >= 0 ? fi : _reorderResumeIndex;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (mounted) {
      setState(() => _reorderMode = value);
    } else {
      _reorderMode = value;
    }
    widget.onReorderModeChanged?.call(value);
    if (!value) {
      final idx = _reorderResumeIndex;
      _reorderResumeIndex = null;
      if (!mounted) return;
      if (idx != null && idx >= 0 && idx < _focusNodes.length) {
        _pendingFocusIndex = idx;
        runNextFrame(_applyPendingFocus);
      } else {
        DocumentEditorRegistry.restoreActiveWritingFocus();
      }
    }
  }

  List<DescriptionTextRange> _descriptionRanges(String? segmentId) {
    final host = widget.hostEmbed;
    if (host == null || segmentId == null) return const [];
    return descriptionRangesForSegment(
      state: widget.state,
      fileId: host.fileId,
      segmentId: segmentId,
    );
  }

  List<DescriptionTextRange> _taskDescriptionRanges(int index) {
    final id = index >= 0 && index < _taskIds.length ? _taskIds[index] : null;
    final task = id == null ? null : _taskById(id);
    return descriptionRangesFromLinks(task?.descriptionLinks ?? const []);
  }

  String _taskSegmentId(int index) {
    final id = index >= 0 && index < _taskIds.length ? _taskIds[index] : null;
    if (id != null) return taskIdSegmentId(id);
    return 'task:pending:$index';
  }

  Future<void> _connectInfo({String? segmentId}) async {
    final host = widget.hostEmbed;
    if (host == null) return;
    await connectInfoFromMark(
      context: context,
      state: widget.state,
      host: host,
      segmentId: segmentId,
    );
    if (mounted) setState(() {});
  }

  Future<void> _connectTaskInfo(int index) async {
    final id = index >= 0 && index < _taskIds.length ? _taskIds[index] : null;
    if (id == null) return;
    await connectInfoFromTask(
      context: context,
      state: widget.state,
      taskId: id,
      fileId: widget.hostEmbed?.fileId,
    );
    if (mounted) setState(() {});
  }

  Future<void> _showTaskMenu(TapDownDetails details, int index) async {
    final id = index >= 0 && index < _taskIds.length ? _taskIds[index] : null;
    final task = id == null ? null : _taskById(id);
    final extras = task == null
        ? const <AppContextMenuEntry>[]
        : (widget.extraMenuEntries?.call(task) ?? const []);
    final onReorderChanged = widget.onReorderModeChanged;

    final ranges = _taskDescriptionRanges(index);
    await DocumentContextMenu.showTaskListMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      extraEntries: extras,
      includeAssignView: widget.includeAssignView,
      includeConnectInfo: true,
      includeDisconnectInfo: descriptionRangeCoveringMark(ranges) != null,
      onAction: (action) async {
        if (action == 'text:connect_info') {
          await _connectTaskInfo(index);
          return;
        }
        if (action == 'text:disconnect_info') {
          await disconnectInfoAtMark(state: widget.state, ranges: ranges);
          if (mounted) setState(() {});
          return;
        }
        if (action == 'tasks:reorder_mode') {
          if (mounted) {
            _setReorderMode(true);
          } else {
            onReorderChanged?.call(true);
          }
          return;
        }
        if (action == 'tasks:assign_view') {
          var ids = markedTaskIds();
          if (ids.isEmpty && id != null) ids = [id];
          if (ids.isEmpty || !mounted) return;
          await showAssignTaskViewDialog(
            context: context,
            state: widget.state,
            taskIds: ids,
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

  Widget _dropGap({required bool targetDone, required int indexInZone}) {
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

  Widget _taskChrome({required Widget mark, required Widget title}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: mark),
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
    final titleText = _controllers[index].text.trim();
    final mark = TaskMark(done: _done[index], compact: true, onToggle: () {});
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
    return Align(alignment: AlignmentDirectional.centerStart, child: chip);
  }

  Widget _keyedTaskRow(int index) {
    if (index < 0 || index >= _rowKeys.length) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: ObjectKey(_rowKeys[index]),
      child: _taskRow(index),
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
    final complimentary = task?.isComplimentaryTask ?? false;
    final mark = TaskMark(
      done: _done[index],
      compact: true,
      onToggle: complimentary ? null : () => unawaited(_toggle(index)),
    );
    final title = complimentary && task != null
        ? _complimentaryTitle(task, titleStyle)
        : FormattedTextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        segmentId: _taskSegmentId(index),
        documentBaseOffset: widget.documentBaseOffset,
        style: titleStyle,
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
        taskId: id,
        descriptionRanges: _taskDescriptionRanges(index),
        onDescriptionActivate: (range) =>
            openDescriptionTarget(state: widget.state, link: range.link),
        onDescriptionAnchorsChanged: (ranges) {
          unawaited(persistRemappedDescriptionAnchors(widget.state, ranges));
        },
        onArrowExitAbove: () =>
            _arrowFromLine(_hasTitleLine ? index + 1 : index, goingDown: false),
        onArrowExitBelow: () =>
            _arrowFromLine(_hasTitleLine ? index + 1 : index, goingDown: true),
      );

    return _taskChrome(mark: mark, title: title);
  }

  Widget _complimentaryTitle(Task task, TextStyle style) {
    final s = widget.state.strings;
    Automation? automation;
    if (task.sourceAutomationId != null) {
      for (final item in widget.state.automations) {
        if (item.id == task.sourceAutomationId) automation = item;
      }
    }
    final name = automation == null
        ? task.title
        : widget.state.automationDisplayName(automation);
    final label = task.isReviewComplimentary
        ? s.complimentaryReviewTitle(name)
        : s.complimentaryInputTitle(name);
    final reviewPending = automation?.hasPendingReview ?? false;
    final clickable = task.isInputComplimentary
        ? !task.isDone && !task.complimentaryInputReceived
        : reviewPending && !task.isDone;
    final tooltip = task.isInputComplimentary
        ? (task.complimentaryInputReceived || task.isDone
              ? s['inputAlreadyReceived']
              : null)
        : (reviewPending && !task.isDone ? s['reviewInProcess'] : null);
    final text = Text(label, style: style);
    final child = clickable
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => unawaited(_openComplimentary(task)),
              child: text,
            ),
          )
        : text;
    return tooltip == null ? child : Tooltip(message: tooltip, child: child);
  }

  Future<void> _openComplimentary(Task task) async {
    final automationId = task.sourceAutomationId;
    if (automationId == null) return;
    Automation? automation;
    for (final item in widget.state.automations) {
      if (item.id == automationId) automation = item;
    }
    if (automation == null) return;
    if (task.isInputComplimentary) {
      if (task.isDone || task.complimentaryInputReceived) return;
      await showComplimentaryInputDialog(
        context: context,
        state: widget.state,
        automation: automation,
      );
      return;
    }
    final status = await widget.state.complimentaryReviewStatus(automationId);
    if (!mounted) return;
    final fileIds = [
      for (final id in status['file_ids'] as List? ?? const [])
        if (id is int) id,
    ];
    if (fileIds.isEmpty) return;
    for (final fileId in fileIds) {
      if (!mounted) return;
      await openPendingReviewForFile(context, widget.state, fileId);
    }
    await widget.state.completeComplimentaryReview(automationId);
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeCount;
    final doneCount = _controllers.length - activeCount;
    final showDoneHeader = doneCount > 0;
    final s = widget.state.strings;
    final compact = widget.compactMode;

    _syncFlowOrder();

    final list = Column(
      crossAxisAlignment: compact || _reorderMode
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: [
        if (_bridge.showListTitle && !compact && !_reorderMode)
          FormattedTextField(
            controller: _titleController,
            focusNode: _titleFocus,
            segmentId: _titleSegmentId,
            documentBaseOffset: widget.documentBaseOffset,
            style: AppTypography.noteTitleStyle,
            // Multi-line field (one visual line) — avoids single-line vertical
            // caret intents that mark the whole title; newlines still stripped.
            maxLines: null,
            minLines: 1,
            stripNewlines: true,
            onChanged: (_) => _scheduleTitleSave(),
            onEnter: _onTitleEnter,
            onBackspaceAtStart: () async {
              if (!imeFieldLooksEmpty(_titleController.text)) return;
              if (_controllers.length == 1 &&
                  imeFieldLooksEmpty(_controllers.first.text) &&
                  widget.onDeleteObject != null) {
                widget.onDeleteObject!();
              }
            },
            onSecondaryTapDown: (d) {
              final onReorderChanged = widget.onReorderModeChanged;
              final ranges = _descriptionRanges(widget.listTitleSegmentId);
              unawaited(
                DocumentContextMenu.showTaskListMenu(
                  context: context,
                  globalPosition: d.globalPosition,
                  strings: widget.state.strings,
                  includeAssignView: false,
                  includeConnectInfo: widget.hostEmbed != null,
                  includeDisconnectInfo:
                      descriptionRangeCoveringMark(ranges) != null,
                  onAction: (action) async {
                    if (action == 'text:connect_info') {
                      await _connectInfo(segmentId: widget.listTitleSegmentId);
                      return;
                    }
                    if (action == 'text:disconnect_info') {
                      await disconnectInfoAtMark(
                        state: widget.state,
                        ranges: ranges,
                      );
                      if (mounted) setState(() {});
                      return;
                    }
                    if (action == 'tasks:reorder_mode') {
                      if (mounted) {
                        _setReorderMode(true);
                      } else {
                        onReorderChanged?.call(true);
                      }
                      return;
                    }
                    await runBlockTextAction(action);
                  },
                ),
              );
            },
            descriptionRanges: _descriptionRanges(widget.listTitleSegmentId),
            onDescriptionActivate: widget.hostEmbed == null
                ? null
                : (range) => openDescriptionTarget(
                    state: widget.state,
                    link: range.link,
                  ),
            onDescriptionAnchorsChanged: widget.hostEmbed == null
                ? null
                : (ranges) {
                    unawaited(
                      persistRemappedDescriptionAnchors(widget.state, ranges),
                    );
                  },
            onArrowExitAbove: () => _arrowFromLine(0, goingDown: false),
            onArrowExitBelow: () => _arrowFromLine(0, goingDown: true),
          ),
        if (_bridge.showListTitle && !compact && !_reorderMode)
          const SizedBox(height: 4),
        if (showDoneHeader) _zoneLabel(s['tasksActive']),
        for (var i = 0; i < activeCount; i++) _keyedTaskRow(i),
        _dropGap(targetDone: false, indexInZone: activeCount),
        if (showDoneHeader) ...[
          _zoneLabel(s['tasksDone']),
          for (var i = activeCount; i < _controllers.length; i++)
            _keyedTaskRow(i),
          _dropGap(targetDone: true, indexInZone: doneCount),
        ],
      ],
    );

    final wrapped = DocumentTextFlowScope(flow: _flow, child: list);
    if (!_reorderMode) return wrapped;

    return TapRegion(
      onTapOutside: (_) => _setReorderMode(false),
      child: wrapped,
    );
  }
}
