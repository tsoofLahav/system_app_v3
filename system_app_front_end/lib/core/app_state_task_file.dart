part of 'app_state.dart';

extension AppStateTaskFile on AppState {
  Future<void> _runFlipDrag(Future<void> Function() action) {
    final previous = _flipDragQueue ?? Future.value();
    final next = previous.then((_) => action());
    _flipDragQueue = next;
    return next;
  }

  List<int> _taskIdsInViewOrder(
    String viewType,
    Iterable<Task> desiredOrder, {
    int? ensureIncludedTaskId,
  }) {
    final ids = <int>[];
    for (final task in desiredOrder) {
      if (task.id == ensureIncludedTaskId ||
          viewTypeForTask(task.id) == viewType) {
        ids.add(task.id);
      }
    }
    return ids;
  }

  int _insertIndexInZoneAfter(
    List<Task> listTasks,
    Task afterTask,
    bool targetDone,
  ) {
    final parts = partitionTasks(listTasks);
    final zone = targetDone ? parts.done : parts.active;
    if (afterTask.isDone != targetDone) return zone.length;
    final index = zone.indexWhere((t) => t.id == afterTask.id);
    return index < 0 ? zone.length : index + 1;
  }

  Map<int, Block> _listBlockByTaskIdForFile(AppFile file) {
    final map = <int, Block>{};
    for (final block in _blocksForFile(file)) {
      if (block.type != 'task_list') continue;
      for (final task in orderedTasksForFile(file, block)) {
        map[task.id] = block;
      }
    }
    return map;
  }

  List<Task> _orderedTasksInView(String viewType, AppFile file) {
    final tasks = <Task>[];
    for (final block in _blocksForFile(file)) {
      if (block.type != 'task_list') continue;
      tasks.addAll(orderedTasksForFile(file, block));
    }
    final inView = tasks.where((t) => viewTypeForTask(t.id) == viewType).toList();
    inView.sort((a, b) {
      final order = orderIndexForTask(a.id).compareTo(orderIndexForTask(b.id));
      if (order != 0) return order;
      return a.id.compareTo(b.id);
    });
    return inView;
  }

  List<Task> orderedTasksForFile(AppFile file, Block listBlock) {
    return orderedTasksForListBlock(
      _blocksForFile(file),
      listBlock,
      _tasksByBlockIdForFile(file),
    );
  }

  Block? taskRowBlockInFile(AppFile file, Task task) {
    for (final block in _blocksForFile(file)) {
      if (block.type == 'task' && block.content['task_id'] == task.id) {
        return block;
      }
    }
    return null;
  }

  Task? _taskForCreatedBlock(Block taskBlock, Block listBlock) {
    final taskId = taskBlock.content['task_id'] as int?;
    if (taskId == null) return null;
    final tasks = broughtFile?.tasksByBlockId[listBlock.id] ??
        selectedDetail?.tasksByBlockId[listBlock.id] ??
        [];
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<Task?> createTaskInFileAfter({
    required AppFile file,
    required Block listBlock,
    Task? afterTask,
    String title = '',
    String status = 'active',
    String? flipViewType,
  }) async {
    final topic = selectedTopic;
    if (topic == null) return null;

    final afterRow = afterTask != null
        ? taskRowBlockInFile(file, afterTask)
        : null;
    final blocks = _blocksForFile(file);
    final listInsertIndex = afterRow != null
        ? _listInsertIndexAfterBlock(blocks, afterRow)
        : _listInsertIndexForNewTask(file, listBlock);
    final targetIndex = await _shiftBlocksForInsert(file, listInsertIndex);
    final taskBlock = await _createTaskBlock(
      listBlock: listBlock,
      fileId: file.id,
      title: title,
      orderIndex: targetIndex,
      status: status,
    );
    var task = _taskForCreatedBlock(taskBlock, listBlock);
    if (task == null) return null;
    final createdTask = task;

    final targetDone = status == 'done';
    if (afterTask != null) {
      final listTasks = orderedTasksForFile(file, listBlock);
      final mergedIds = mergedTaskIdsAfterZoneInsert(
        listTasks: listTasks,
        task: createdTask,
        targetDone: targetDone,
        insertIndexInZone: _insertIndexInZoneAfter(
          listTasks,
          afterTask,
          targetDone,
        ),
      );
      await reorderTasksInListBlock(file, listBlock, mergedIds);
      task = orderedTasksForFile(file, listBlock).firstWhere(
        (entry) => entry.id == createdTask.id,
      );
    }

    if (flipViewType != null) {
      final listBlockByTaskId = _listBlockByTaskIdForFile(file);
      final currentTask = task;
      final groupTasks = _orderedTasksInView(flipViewType, file)
          .where((entry) => entry.id != currentTask.id)
          .toList();
      final insertIndexInZone = afterTask == null
          ? (targetDone
              ? partitionTasks(groupTasks).done.length
              : partitionTasks(groupTasks).active.length)
          : _insertIndexInZoneAfter(
              [...groupTasks, currentTask],
              afterTask,
              targetDone,
            );
      await _runFlipDrag(
        () => insertTaskInFlipGroupAt(
          file,
          currentTask,
          flipViewType,
          listBlockByTaskId,
          groupTasks: groupTasks,
          targetDone: targetDone,
          insertIndexInZone: insertIndexInZone,
        ),
      );
      task = orderedTasksForFile(file, listBlock).firstWhere(
        (entry) => entry.id == currentTask.id,
      );
    }

    requestBlockFocus(taskBlock.id);
    notifyListeners();
    return task;
  }

  Future<void> deleteTaskInFile(AppFile file, Task task) async {
    if (selectedTopic == null) return;
    final row = taskRowBlockInFile(file, task);
    final listBlock = _listBlockByTaskIdForFile(file)[task.id];
    final remainingIds = listBlock == null
        ? null
        : orderedTasksForFile(file, listBlock)
            .where((entry) => entry.id != task.id)
            .map((entry) => entry.id)
            .toList();

    try {
      await _taskService.deleteTask(task.id);
    } catch (_) {
      await _refreshAfterFileMutation(file);
      rethrow;
    }

    if (row != null) {
      try {
        await _blockService.deleteBlock(row.id);
      } catch (_) {
        // Row anchor may already be gone or referenced elsewhere.
      }
    }

    _removeTaskFromFileCaches(file, task, row);
    _taskViewMemberships = _taskViewMemberships
        .where((membership) => membership.taskId != task.id)
        .toList();

    if (listBlock != null &&
        remainingIds != null &&
        remainingIds.isNotEmpty) {
      try {
        await reorderTasksInListBlock(file, listBlock, remainingIds);
      } catch (_) {}
    }

    notifyListeners();
  }

  void _removeTaskFromFileCaches(AppFile file, Task task, Block? rowBlock) {
    if (broughtFile?.file.id == file.id) {
      final guest = broughtFile!;
      final nextBlocks = rowBlock == null
          ? guest.blocks
          : guest.blocks.where((block) => block.id != rowBlock.id).toList();
      final nextTasksByBlockId = <int, List<Task>>{};
      for (final entry in guest.tasksByBlockId.entries) {
        nextTasksByBlockId[entry.key] = entry.value
            .where((entryTask) => entryTask.id != task.id)
            .toList();
      }
      broughtFile = guest.copyWith(
        blocks: nextBlocks,
        tasksByBlockId: nextTasksByBlockId,
      );
      return;
    }

    final detail = selectedDetail;
    if (detail == null) return;
    if (rowBlock != null) {
      detail.blocksByFileId[file.id] = (detail.blocksByFileId[file.id] ?? [])
          .where((block) => block.id != rowBlock.id)
          .toList();
    }
    for (final entry in detail.tasksByBlockId.entries.toList()) {
      detail.tasksByBlockId[entry.key] = entry.value
          .where((entryTask) => entryTask.id != task.id)
          .toList();
    }
  }

  Future<void> pasteTasksInFileAfter({
    required AppFile file,
    required Block listBlock,
    required Task afterTask,
    required List<String> lines,
    required String status,
  }) async {
    Task? cursor = afterTask;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      cursor = await createTaskInFileAfter(
        file: file,
        listBlock: listBlock,
        afterTask: cursor,
        title: trimmed,
        status: status,
      );
    }
  }

  void _patchFileInCaches(AppFile file) {
    final detail = selectedDetail;
    if (detail != null) {
      _applyOptimisticFiles(
        detail.files.map((f) => f.id == file.id ? file : f).toList(),
      );
    } else if (broughtFile?.file.id == file.id) {
      broughtFile = broughtFile!.copyWith(file: file);
      notifyListeners();
    }
  }

  Future<void> setFileTasksFlipByView(AppFile file, bool enabled) async {
    final nextSettings = Map<String, dynamic>.from(file.settings);
    if (enabled) {
      nextSettings['tasks_flip_by_view'] = true;
    } else {
      nextSettings.remove('tasks_flip_by_view');
    }
    final updated = await _fileService.updateFile(file.id, {
      'settings': nextSettings,
    });
    _patchFileInCaches(updated);
  }

  void _replaceTasksForListBlock(int listBlockId, List<Task> tasks) {
    if (broughtFile != null) {
      final guest = broughtFile!;
      broughtFile = guest.copyWith(
        tasksByBlockId: {
          ...guest.tasksByBlockId,
          listBlockId: tasks,
        },
      );
      return;
    }
    final detail = selectedDetail;
    if (detail == null) return;
    detail.tasksByBlockId[listBlockId] = tasks;
  }

  Future<void> reorderTasksInListBlock(
    AppFile file,
    Block listBlock,
    List<int> orderedTaskIds,
  ) async {
    if (orderedTaskIds.isEmpty) return;
    try {
      final updated = await _taskService.reorderTasksInListBlock(
        listBlock.id,
        orderedTaskIds,
      );
      _replaceTasksForListBlock(listBlock.id, updated);
      notifyListeners();
    } catch (_) {
      await _refreshAfterFileMutation(file);
      rethrow;
    }
  }

  Future<void> reorderTasksInListZone(
    AppFile file,
    Block listBlock, {
    required bool done,
    required int oldIndex,
    required int newIndex,
  }) async {
    final all = orderedTasksForFile(file, listBlock);
    final parts = partitionTasks(all);
    final zone = done
        ? List<Task>.from(parts.done)
        : List<Task>.from(parts.active);
    if (oldIndex < 0 ||
        oldIndex >= zone.length ||
        newIndex < 0 ||
        newIndex > zone.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= zone.length) return;
    final moved = zone.removeAt(oldIndex);
    zone.insert(target, moved);
    final mergedIds = done
        ? [...parts.active.map((t) => t.id), ...zone.map((t) => t.id)]
        : [...zone.map((t) => t.id), ...parts.done.map((t) => t.id)];
    await reorderTasksInListBlock(file, listBlock, mergedIds);
  }

  Future<void> reorderTasksInFlipGroup(
    AppFile file,
    String? viewType,
    Map<int, Block> listBlockByTaskId, {
    required List<Task> groupTasks,
    required bool done,
    required int oldIndex,
    required int newIndex,
  }) async {
    final baseGroup = viewType != null
        ? _orderedTasksInView(viewType, file)
        : groupTasks;
    final parts = partitionTasks(baseGroup);
    final zone = done
        ? List<Task>.from(parts.done)
        : List<Task>.from(parts.active);
    if (oldIndex < 0 ||
        oldIndex >= zone.length ||
        newIndex < 0 ||
        newIndex > zone.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= zone.length) return;
    final moved = zone.removeAt(oldIndex);
    zone.insert(target, moved);
    final merged = done
        ? [...parts.active, ...zone]
        : [...zone, ...parts.done];

    if (viewType != null) {
      final taskIds = _taskIdsInViewOrder(
        viewType,
        merged,
        ensureIncludedTaskId: moved.id,
      );
      if (taskIds.isEmpty) return;
      final updated = await _taskViewService.reorderViewGroup(
        viewType: viewType,
        taskIds: taskIds,
      );
      for (final membership in updated) {
        _taskViewMemberships = _taskViewMemberships
            .map(
              (m) => m.id == membership.id
                  ? m.copyWith(orderIndex: membership.orderIndex)
                  : m,
            )
            .toList();
      }
      notifyListeners();
      return;
    }

    final byListBlock = <int, List<int>>{};
    for (final task in merged) {
      final listBlock = listBlockByTaskId[task.id];
      if (listBlock == null) continue;
      byListBlock.putIfAbsent(listBlock.id, () => []).add(task.id);
    }
    for (final entry in byListBlock.entries) {
      final listBlock = listBlockByTaskId[entry.value.first];
      if (listBlock == null) continue;
      await reorderTasksInListBlock(file, listBlock, entry.value);
    }
  }

  Future<void> moveTaskToListBlock(
    AppFile file,
    Task task,
    Block targetListBlock, {
    Task? afterTask,
  }) async {
    final all = orderedTasksForFile(file, targetListBlock);
    final parts = partitionTasks(all);
    final targetDone = afterTask != null ? afterTask.isDone : false;
    final zone = targetDone ? parts.done : parts.active;
    final insertIndex = afterTask != null
        ? zone.indexWhere((t) => t.id == afterTask.id) + 1
        : zone.length;
    await moveTaskToListBlockAtIndex(
      file,
      task,
      targetListBlock,
      targetDone: targetDone,
      insertIndexInZone: insertIndex.clamp(0, zone.length),
    );
  }

  Future<void> moveTaskToListBlockAtIndex(
    AppFile file,
    Task task,
    Block targetListBlock, {
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    try {
      final result = await _taskService.moveTaskToListBlock(
        blockId: targetListBlock.id,
        taskId: task.id,
        insertIndex: insertIndexInZone,
        targetDone: targetDone,
      );
      _replaceTasksForListBlock(targetListBlock.id, result.targetTasks);
      final sourceBlockId = result.sourceBlockId;
      if (sourceBlockId != null && sourceBlockId != targetListBlock.id) {
        _replaceTasksForListBlock(sourceBlockId, result.sourceTasks);
      }
      notifyListeners();
    } catch (_) {
      await _refreshAfterFileMutation(file);
      rethrow;
    }
  }

  Future<void> reorderTaskAcrossZonesInListBlock(
    AppFile file,
    Block listBlock,
    Task task, {
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    await moveTaskToListBlockAtIndex(
      file,
      task,
      listBlock,
      targetDone: targetDone,
      insertIndexInZone: insertIndexInZone,
    );
  }

  Future<void> insertTaskInFlipGroupAt(
    AppFile file,
    Task task,
    String? targetViewType,
    Map<int, Block> listBlockByTaskId, {
    required List<Task> groupTasks,
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    final parts = partitionTasks(groupTasks);
    final active = List<Task>.from(parts.active)
      ..removeWhere((t) => t.id == task.id);
    final done = List<Task>.from(parts.done)..removeWhere((t) => t.id == task.id);
    final zone = targetDone ? done : active;
    zone.insert(insertIndexInZone.clamp(0, zone.length), task);
    final merged = [...active, ...done];
    final globalIndex = merged.indexWhere((t) => t.id == task.id);

    final currentView = viewTypeForTask(task.id);
    if (currentView != targetViewType) {
      await assignTaskView(
        task,
        targetViewType,
        orderIndex: targetViewType != null ? globalIndex : null,
      );
    }

    if (targetViewType != null) {
      final taskIds = _taskIdsInViewOrder(
        targetViewType,
        merged,
        ensureIncludedTaskId: task.id,
      );
      if (taskIds.isNotEmpty) {
        final updated = await _taskViewService.reorderViewGroup(
          viewType: targetViewType,
          taskIds: taskIds,
        );
        for (final membership in updated) {
          _taskViewMemberships = _taskViewMemberships
              .map(
                (m) => m.id == membership.id
                    ? m.copyWith(orderIndex: membership.orderIndex)
                    : m,
              )
              .toList();
        }
        notifyListeners();
      }
    } else {
      final byListBlock = <int, List<int>>{};
      for (final entry in merged) {
        final listBlock = listBlockByTaskId[entry.id];
        if (listBlock == null) continue;
        byListBlock.putIfAbsent(listBlock.id, () => []).add(entry.id);
      }
      for (final entry in byListBlock.entries) {
        final listBlock = listBlockByTaskId[entry.value.first];
        if (listBlock == null) continue;
        await reorderTasksInListBlock(file, listBlock, entry.value);
      }
    }

    await _ensureTaskStatusForDrop(task, targetDone);
  }

  Future<void> applyTaskDrop({
    required AppFile file,
    required TaskDragPayload payload,
    required Block targetListBlock,
    required String? targetViewType,
    required bool targetDone,
    required int insertIndex,
    required int sourceIndexInZone,
    required int targetZoneLength,
    required bool isFlipMode,
    required bool allowCrossBoundary,
    Map<int, Block>? listBlockByTaskId,
    List<Task>? flipGroupTasks,
  }) async {
    Future<void> run() async {
      final action = resolveTaskDrop(
      payload: payload,
      sourceIndexInZone: sourceIndexInZone,
      target: TaskDropTarget(
        listBlockId: targetListBlock.id,
        viewType: targetViewType,
        done: targetDone,
        insertIndex: insertIndex,
      ),
      isFlipMode: isFlipMode,
      allowCrossBoundary: allowCrossBoundary,
      zoneLength: targetZoneLength,
    );

    switch (action.kind) {
      case TaskDropKind.noop:
        return;
      case TaskDropKind.reorder:
        if (isFlipMode &&
            flipGroupTasks != null &&
            listBlockByTaskId != null) {
          await reorderTasksInFlipGroup(
            file,
            targetViewType,
            listBlockByTaskId,
            groupTasks: flipGroupTasks,
            done: payload.sourceDone,
            oldIndex: action.oldIndex!,
            newIndex: action.newIndex!,
          );
        } else {
          await reorderTasksInListZone(
            file,
            targetListBlock,
            done: payload.sourceDone,
            oldIndex: action.oldIndex!,
            newIndex: action.newIndex!,
          );
        }
        return;
      case TaskDropKind.moveAcrossZones:
        if (isFlipMode && flipGroupTasks != null && listBlockByTaskId != null) {
          await insertTaskInFlipGroupAt(
            file,
            payload.task,
            targetViewType,
            listBlockByTaskId,
            groupTasks: flipGroupTasks,
            targetDone: targetDone,
            insertIndexInZone: insertIndex,
          );
        } else {
          await reorderTaskAcrossZonesInListBlock(
            file,
            targetListBlock,
            payload.task,
            targetDone: targetDone,
            insertIndexInZone: insertIndex,
          );
        }
        return;
      case TaskDropKind.moveToListBlock:
        await moveTaskToListBlockAtIndex(
          file,
          payload.task,
          targetListBlock,
          targetDone: targetDone,
          insertIndexInZone: insertIndex,
        );
        return;
      case TaskDropKind.assignView:
        if (listBlockByTaskId == null || flipGroupTasks == null) return;
        await insertTaskInFlipGroupAt(
          file,
          payload.task,
          targetViewType,
          listBlockByTaskId,
          groupTasks: flipGroupTasks,
          targetDone: targetDone,
          insertIndexInZone: insertIndex,
        );
        return;
    }
    }

    if (isFlipMode) {
      await _runFlipDrag(run);
    } else {
      await run();
    }
  }

  Future<void> _ensureTaskStatusForDrop(Task task, bool targetDone) async {
    if (task.isDone == targetDone) return;
    final data = await _taskService.updateTaskRaw(task.id, {
      'status': targetDone ? 'done' : 'active',
    });
    final updated = Task.fromJson(data);
    _applyTaskUpdate(updated);
    notifyListeners();
  }
}
