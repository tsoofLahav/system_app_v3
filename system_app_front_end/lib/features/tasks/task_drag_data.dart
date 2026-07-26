import '../../core/models/task.dart';

/// Drag payload for reordering tasks within an inline task list.
class TaskDragPayload {
  const TaskDragPayload({
    required this.task,
    required this.sourceListId,
    required this.sourceDone,
  });

  final Task task;
  final int sourceListId;
  final bool sourceDone;
}
