import 'models/block.dart';
import 'models/task.dart';
import 'registry/view_registry.dart';
import 'task_list_order.dart';

List<Block> sortedBlocksForFile(List<Block> blocks) {
  final copy = List<Block>.from(blocks);
  copy.sort((a, b) {
    final orderCompare = (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0);
    if (orderCompare != 0) return orderCompare;
    return a.id.compareTo(b.id);
  });
  return copy;
}

class TaskListRegion {
  const TaskListRegion({required this.startIndex, required this.endIndex});

  final int startIndex;
  final int endIndex;
}

TaskListRegion taskListRegion(List<Block> fileBlocks, Block listBlock) {
  final blocks = sortedBlocksForFile(fileBlocks);
  var startIndex = -1;
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].id == listBlock.id) {
      startIndex = i;
      break;
    }
  }
  if (startIndex < 0) {
    return const TaskListRegion(startIndex: 0, endIndex: 0);
  }

  var endIndex = blocks.length;
  for (var i = startIndex + 1; i < blocks.length; i++) {
    if (blocks[i].type == 'task_list') {
      endIndex = i;
      break;
    }
  }
  return TaskListRegion(startIndex: startIndex, endIndex: endIndex);
}

int? taskIdFromBlockContent(Map<String, dynamic> content) {
  final value = content['task_id'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

Map<int, Block> taskRowBlocksByTaskId(List<Block> fileBlocks) {
  final rowByTaskId = <int, Block>{};
  for (final block in fileBlocks) {
    if (block.type != 'task') continue;
    final taskId = taskIdFromBlockContent(block.content);
    if (taskId != null) rowByTaskId[taskId] = block;
  }
  return rowByTaskId;
}

List<Task> orderedTasksForListBlock(
  List<Block> fileBlocks,
  Block listBlock,
  Map<int, List<Task>> tasksByBlockId,
) {
  final tasks = tasksByBlockId[listBlock.id] ?? const <Task>[];
  if (tasks.isEmpty) return const [];

  final ordered = List<Task>.from(tasks);
  ordered.sort((a, b) {
    final statusCompare = (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0);
    if (statusCompare != 0) return statusCompare;
    final orderCompare =
        a.listOrderIndex.compareTo(b.listOrderIndex);
    if (orderCompare != 0) return orderCompare;
    return a.id.compareTo(b.id);
  });
  return ordered;
}

class TaskInFile {
  const TaskInFile({
    required this.task,
    required this.listBlock,
    required this.rowBlock,
  });

  final Task task;
  final Block listBlock;
  final Block? rowBlock;
}

List<TaskInFile> allTasksInFile(
  List<Block> fileBlocks,
  Map<int, List<Task>> tasksByBlockId,
) {
  final blocks = sortedBlocksForFile(fileBlocks);
  final listBlocks = blocks.where((b) => b.type == 'task_list').toList();
  final entries = <TaskInFile>[];
  for (final listBlock in listBlocks) {
    final tasks = orderedTasksForListBlock(
      blocks,
      listBlock,
      tasksByBlockId,
    );
  for (final task in tasks) {
      Block? rowBlock;
      for (final block in blocks) {
        if (block.type == 'task' && block.content['task_id'] == task.id) {
          rowBlock = block;
          break;
        }
      }
      entries.add(
        TaskInFile(task: task, listBlock: listBlock, rowBlock: rowBlock),
      );
    }
  }
  return entries;
}

class TaskViewGroup {
  const TaskViewGroup({
    required this.viewType,
    required this.label,
    required this.tasks,
  });

  final String? viewType;
  final String label;
  final List<Task> tasks;
}

List<TaskViewGroup> groupTasksByView(
  Iterable<Task> tasks,
  String? Function(int taskId) membershipViewForTask, {
  int Function(int taskId)? membershipOrderForTask,
  int Function(int taskId)? blockOrderForTask,
  String unassignedLabel = 'Unassigned',
}) {
  final byView = <String?, List<Task>>{};
  for (final task in tasks) {
    final viewType = membershipViewForTask(task.id);
    byView.putIfAbsent(viewType, () => []).add(task);
  }

  void sortGroup(List<Task> group, {required bool useBlockOrder}) {
    if (useBlockOrder && blockOrderForTask != null) {
      group.sort(
        (a, b) => blockOrderForTask(a.id).compareTo(blockOrderForTask(b.id)),
      );
      return;
    }
    if (membershipOrderForTask == null) return;
    group.sort(
      (a, b) => membershipOrderForTask(a.id).compareTo(
        membershipOrderForTask(b.id),
      ),
    );
  }

  final groups = <TaskViewGroup>[];
  for (final view in ViewRegistry.views) {
    final viewTasks = byView.remove(view.type);
    if (viewTasks == null || viewTasks.isEmpty) continue;
    sortGroup(viewTasks, useBlockOrder: false);
    groups.add(
      TaskViewGroup(
        viewType: view.type,
        label: view.label,
        tasks: viewTasks,
      ),
    );
  }

  final unassigned = byView.remove(null);
  if (unassigned != null && unassigned.isNotEmpty) {
    sortGroup(unassigned, useBlockOrder: true);
    groups.add(
      TaskViewGroup(
        viewType: null,
        label: unassignedLabel,
        tasks: unassigned,
      ),
    );
  }
  return groups;
}

int listInsertIndexForNewTask(List<Block> fileBlocks, Block listBlock) {
  final blocks = sortedBlocksForFile(fileBlocks);
  final region = taskListRegion(blocks, listBlock);
  for (var i = region.endIndex - 1; i > region.startIndex; i--) {
    if (blocks[i].type == 'task') return i + 1;
  }
  return region.startIndex + 1;
}

int listInsertIndexAfterTaskBlock(List<Block> fileBlocks, Block afterTaskBlock) {
  final blocks = sortedBlocksForFile(fileBlocks);
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].id == afterTaskBlock.id) return i + 1;
  }
  return blocks.length;
}

/// Build merged task ids (active then done) after inserting [task] in a zone.
List<int> mergedTaskIdsAfterZoneInsert({
  required List<Task> listTasks,
  required Task task,
  required bool targetDone,
  required int insertIndexInZone,
}) {
  final parts = partitionTasks(listTasks);
  final active = List<Task>.from(parts.active)
    ..removeWhere((t) => t.id == task.id);
  final done = List<Task>.from(parts.done)..removeWhere((t) => t.id == task.id);
  final zone = targetDone ? done : active;
  zone.insert(insertIndexInZone.clamp(0, zone.length), task);
  return [...active, ...done].map((t) => t.id).toList();
}
