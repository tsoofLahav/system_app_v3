import '../../core/models/block.dart';
import '../../core/models/task.dart';

class TaskDragData {
  const TaskDragData({
    required this.task,
    required this.sourceListBlock,
    required this.done,
    this.flipViewType,
  });

  final Task task;
  final Block? sourceListBlock;
  final bool done;
  final String? flipViewType;
}
