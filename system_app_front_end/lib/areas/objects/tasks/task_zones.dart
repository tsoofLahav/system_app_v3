import '../data/task.dart';

/// Active and Done are filtered projections of one context-specific order.
class TaskZones {
  TaskZones.fromOrdered(List<Task> tasks) : ordered = List.unmodifiable(tasks);

  final List<Task> ordered;
  List<Task> get active => ordered.where((t) => !t.isDone).toList();
  List<Task> get done => ordered.where((t) => t.isDone).toList();

  /// Display order only. Never persist this concatenation.
  List<Task> get all => [...active, ...done];
  List<int> get orderedIds => [for (final t in ordered) t.id];

  static TaskZones fromTasks(Iterable<Task> tasks) {
    final list = [...tasks]
      ..sort((a, b) {
        final order = a.listOrderIndex.compareTo(b.listOrderIndex);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    return TaskZones.fromOrdered(list);
  }

  TaskZones withStatus(int taskId, bool targetDone) => TaskZones.fromOrdered([
    for (final task in ordered)
      task.id == taskId ? _placed(task, targetDone) : task,
  ]);

  static Task _placed(Task task, bool targetDone) => task.copyWith(
    status: targetDone
        ? 'done'
        : task.isDone
        ? 'active'
        : task.status,
  );

  /// Drop index is in the pre-move visible zone.
  TaskZones moved({
    required int taskId,
    required bool targetDone,
    required int indexInZone,
  }) {
    final task = ordered.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return this;
    final zone = targetDone ? done : active;
    final sourceIndex = zone.indexWhere((t) => t.id == taskId);
    final at = sourceIndex >= 0 && sourceIndex < indexInZone
        ? indexInZone - 1
        : indexInZone;
    return inserted(task: task, targetDone: targetDone, indexInZone: at);
  }

  /// Insert before the target visible sibling, or after its last sibling.
  /// All other tasks retain their relative canonical order.
  TaskZones inserted({
    required Task task,
    required bool targetDone,
    required int indexInZone,
  }) {
    final next = ordered.where((t) => t.id != task.id).toList();
    final zone = next.where((t) => t.isDone == targetDone).toList();
    final at = indexInZone.clamp(0, zone.length);
    final position = at < zone.length
        ? next.indexWhere((t) => t.id == zone[at].id)
        : zone.isNotEmpty
        ? next.indexWhere((t) => t.id == zone.last.id) + 1
        : next.length;
    next.insert(position, _placed(task, targetDone));
    return TaskZones.fromOrdered(next);
  }
}
