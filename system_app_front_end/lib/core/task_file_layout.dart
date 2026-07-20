import 'models/block.dart';
import 'models/task.dart';
import 'registry/view_registry.dart';

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

List<Task> orderedTasksForListBlock(
  List<Block> fileBlocks,
  Block listBlock,
  Map<int, List<Task>> tasksByBlockId,
) {
  final blocks = sortedBlocksForFile(fileBlocks);
  final region = taskListRegion(blocks, listBlock);
  final taskById = {
    for (final task in tasksByBlockId[listBlock.id] ?? const <Task>[])
      task.id: task,
  };
  final ordered = <Task>[];
  for (var i = region.startIndex + 1; i < region.endIndex; i++) {
    final block = blocks[i];
    if (block.type != 'task') continue;
    final taskId = block.content['task_id'] as int?;
    if (taskId == null) continue;
    final task = taskById[taskId];
    if (task != null) ordered.add(task);
  }
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
  final Block rowBlock;
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
      if (rowBlock != null) {
        entries.add(
          TaskInFile(task: task, listBlock: listBlock, rowBlock: rowBlock),
        );
      }
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
  String unassignedLabel = 'Unassigned',
}) {
  final byView = <String?, List<Task>>{};
  for (final task in tasks) {
    final viewType = membershipViewForTask(task.id);
    byView.putIfAbsent(viewType, () => []).add(task);
  }

  final groups = <TaskViewGroup>[];
  for (final view in ViewRegistry.views) {
    final viewTasks = byView.remove(view.type);
    if (viewTasks == null || viewTasks.isEmpty) continue;
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
