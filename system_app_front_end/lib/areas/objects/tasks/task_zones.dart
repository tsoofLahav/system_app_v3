import '../data/task.dart';

/// Split tasks into Active / Done zones (canonical [Task.status]).
///
/// Within each zone, order follows [Task.listOrderIndex] unless [byIds] is
/// provided (explicit id order, e.g. view membership order).
class TaskZones {
  const TaskZones({required this.active, required this.done});

  final List<Task> active;
  final List<Task> done;

  List<Task> get all => [...active, ...done];

  List<int> get orderedIds => [for (final t in all) t.id];

  static TaskZones fromTasks(Iterable<Task> tasks) {
    final list = [...tasks];
    list.sort((a, b) {
      final byStatus = (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0);
      if (byStatus != 0) return byStatus;
      final byOrder = a.listOrderIndex.compareTo(b.listOrderIndex);
      if (byOrder != 0) return byOrder;
      return a.id.compareTo(b.id);
    });
    return TaskZones(
      active: [for (final t in list) if (!t.isDone) t],
      done: [for (final t in list) if (t.isDone) t],
    );
  }

  /// Group by status while preserving relative order of [ordered] among each zone.
  static TaskZones fromOrdered(List<Task> ordered) {
    return TaskZones(
      active: [for (final t in ordered) if (!t.isDone) t],
      done: [for (final t in ordered) if (t.isDone) t],
    );
  }

  /// Move [taskId] within/across zones. [indexInZone] is the drop index in the
  /// pre-move zone (insert-before that slot); adjusted when the source sits
  /// earlier in the same zone.
  TaskZones moved({
    required int taskId,
    required bool targetDone,
    required int indexInZone,
  }) {
    Task? moving;
    var sourceIndex = -1;
    var sourceDone = false;
    final nextActive = <Task>[];
    final nextDone = <Task>[];
    for (var i = 0; i < active.length; i++) {
      final t = active[i];
      if (t.id == taskId) {
        moving = t;
        sourceIndex = i;
        sourceDone = false;
      } else {
        nextActive.add(t);
      }
    }
    for (var i = 0; i < done.length; i++) {
      final t = done[i];
      if (t.id == taskId) {
        moving = t;
        sourceIndex = i;
        sourceDone = true;
      } else {
        nextDone.add(t);
      }
    }
    if (moving == null) return this;
    final placed = moving.copyWith(
      status: targetDone
          ? 'done'
          : moving.isDone
              ? 'active'
              : moving.status,
    );
    final zone = targetDone ? nextDone : nextActive;
    var at = indexInZone;
    if (sourceDone == targetDone && sourceIndex >= 0 && sourceIndex < at) {
      at -= 1;
    }
    at = at.clamp(0, zone.length);
    zone.insert(at, placed);
    return TaskZones(active: nextActive, done: nextDone);
  }

  /// Insert [task] into a zone (adding it if it is not already in this set).
  TaskZones inserted({
    required Task task,
    required bool targetDone,
    required int indexInZone,
  }) {
    final nextActive = [for (final t in active) if (t.id != task.id) t];
    final nextDone = [for (final t in done) if (t.id != task.id) t];
    final placed = task.copyWith(
      status: targetDone
          ? 'done'
          : task.isDone
              ? 'active'
              : task.status,
    );
    final zone = targetDone ? nextDone : nextActive;
    final at = indexInZone.clamp(0, zone.length);
    zone.insert(at, placed);
    return TaskZones(active: nextActive, done: nextDone);
  }
}
