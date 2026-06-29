import 'models/task.dart';

/// Split tasks into active and done, preserving input order within each zone.
({List<Task> active, List<Task> done}) partitionTasks(List<Task> tasks) {
  final active = <Task>[];
  final done = <Task>[];
  for (final task in tasks) {
    if (task.isDone) {
      done.add(task);
    } else {
      active.add(task);
    }
  }
  return (active: active, done: done);
}

List<Task> sortTasksById(List<Task> tasks) {
  final copy = List<Task>.from(tasks);
  copy.sort((a, b) => a.id.compareTo(b.id));
  return copy;
}

({List<Task> active, List<Task> done}) partitionTasksById(List<Task> tasks) {
  return partitionTasks(sortTasksById(tasks));
}
