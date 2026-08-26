import '../../../core/app_state.dart';
import '../data/object_embed.dart';
import '../data/task.dart';
import './task_list_bridge.dart';

/// Persistence for an in-file task list embed.
class FileTaskListBridge extends TaskListBridge {
  FileTaskListBridge({
    required this.state,
    required this.embed,
    required this.onRefresh,
  });

  final AppState state;
  ObjectEmbed embed;
  final Future<void> Function() onRefresh;

  int? get _listId => embed.taskListId;

  @override
  List<Task> get remoteTasks => [
        for (final task in embed.tasks ?? const [])
          state.hydrateTask(task),
      ];

  @override
  int get dragGroupId => _listId ?? 0;

  @override
  bool get showListTitle => true;

  @override
  String get listTitle => embed.taskListTitle;

  @override
  Future<void> refresh() => onRefresh();

  @override
  Future<Task> createAfter({
    required String title,
    required String status,
    int? afterTaskId,
  }) {
    final id = _listId;
    if (id == null) {
      throw StateError('Task list has no id');
    }
    return state.createTaskInList(
      id,
      title: title,
      afterTaskId: afterTaskId,
      status: status,
      notify: false,
    );
  }

  @override
  Future<Task?> ensureSeed() async {
    final id = _listId;
    if (id == null || remoteTasks.isNotEmpty) return null;
    return state.createTaskInList(id, title: '', notify: false);
  }

  @override
  Future<void> delete(Task task) =>
      state.deleteTask(task, notify: false);

  @override
  Future<void> updateTitle(Task task, String title) =>
      state.updateTaskTitle(task, title, notify: false);

  @override
  Future<void> updateListTitle(String title) async {
    final id = _listId;
    if (id == null) return;
    await state.updateTaskListTitle(id, title, notify: false);
  }

  @override
  Future<void> moveInZone({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
  }) {
    return state.moveTaskInListZone(
      task: task,
      targetDone: targetDone,
      insertIndexInZone: insertIndexInZone,
      notify: false,
    );
  }

  @override
  Future<void> reorder(List<int> orderedIds) async {
    final id = _listId;
    if (id == null) return;
    await state.reorderTasksInList(id, orderedIds, notify: false);
  }

  @override
  Future<void> markAll({required bool done}) async {
    for (final task in remoteTasks) {
      if (task.isDone == done) continue;
      await state.toggleTaskStatus(task, notify: false);
    }
  }
}
