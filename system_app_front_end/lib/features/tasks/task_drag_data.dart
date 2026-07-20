import '../../core/models/block.dart';
import '../../core/models/task.dart';

/// Payload for grip-initiated task drag (reorder and cross-boundary drops).
class TaskDragPayload {
  const TaskDragPayload({
    required this.task,
    required this.sourceListBlock,
    required this.sourceDone,
    this.sourceViewType,
  });

  final Task task;
  final Block sourceListBlock;
  final bool sourceDone;
  final String? sourceViewType;
}

/// Drop target context for a task zone row or trailing slot.
class TaskDropTarget {
  const TaskDropTarget({
    required this.listBlockId,
    required this.viewType,
    required this.done,
    required this.insertIndex,
  });

  final int listBlockId;
  final String? viewType;
  final bool done;
  final int insertIndex;
}

enum TaskDropKind {
  noop,
  reorder,
  moveAcrossZones,
  moveToListBlock,
  assignView,
}

class TaskDropAction {
  const TaskDropAction._(this.kind, {this.oldIndex, this.newIndex});

  const TaskDropAction.noop() : this._(TaskDropKind.noop);

  const TaskDropAction.reorder({
    required int oldIndex,
    required int newIndex,
  }) : this._(TaskDropKind.reorder, oldIndex: oldIndex, newIndex: newIndex);

  const TaskDropAction.moveAcrossZones()
      : this._(TaskDropKind.moveAcrossZones);

  const TaskDropAction.moveToListBlock()
      : this._(TaskDropKind.moveToListBlock);

  const TaskDropAction.assignView() : this._(TaskDropKind.assignView);

  final TaskDropKind kind;
  final int? oldIndex;
  final int? newIndex;
}

/// Pure drop classification for regular vs flip-by-view mode.
TaskDropAction resolveTaskDrop({
  required TaskDragPayload payload,
  required int sourceIndexInZone,
  required TaskDropTarget target,
  required bool isFlipMode,
  required bool allowCrossBoundary,
  required int zoneLength,
}) {
  if (isFlipMode) {
    final sameView = payload.sourceViewType == target.viewType;
    if (sameView) {
      if (payload.sourceDone == target.done) {
        return _reorderAction(
          sourceIndexInZone,
          target.insertIndex,
          zoneLength: zoneLength,
        );
      }
      return const TaskDropAction.moveAcrossZones();
    }
    if (!allowCrossBoundary) return const TaskDropAction.noop();
    return const TaskDropAction.assignView();
  }

  final sameBlock = payload.sourceListBlock.id == target.listBlockId;
  if (sameBlock) {
    if (payload.sourceDone == target.done) {
      return _reorderAction(
        sourceIndexInZone,
        target.insertIndex,
        zoneLength: zoneLength,
      );
    }
    return const TaskDropAction.moveAcrossZones();
  }
  if (!allowCrossBoundary) return const TaskDropAction.noop();
  return const TaskDropAction.moveToListBlock();
}

TaskDropAction _reorderAction(
  int sourceIndexInZone,
  int insertIndex, {
  required int zoneLength,
}) {
  if (sourceIndexInZone < 0) return const TaskDropAction.noop();
  if (sourceIndexInZone == insertIndex) return const TaskDropAction.noop();
  if (insertIndex >= zoneLength) {
    if (sourceIndexInZone == zoneLength - 1) return const TaskDropAction.noop();
    return TaskDropAction.reorder(
      oldIndex: sourceIndexInZone,
      newIndex: zoneLength,
    );
  }
  final newIndex =
      sourceIndexInZone < insertIndex ? insertIndex + 1 : insertIndex;
  return TaskDropAction.reorder(
    oldIndex: sourceIndexInZone,
    newIndex: newIndex,
  );
}
