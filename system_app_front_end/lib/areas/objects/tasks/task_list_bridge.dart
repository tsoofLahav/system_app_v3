import '../data/task.dart';
import './task_drag_data.dart';

/// Persistence port for [TaskListSurface]. File embeds and view frames each
/// supply a bridge; the surface never imports embeds or view chrome.
abstract class TaskListBridge {
  List<Task> get remoteTasks;

  /// Shared drag namespace — drops only accept matching [TaskDragPayload.sourceListId].
  int get dragGroupId;

  bool get showListTitle;
  String get listTitle;

  Future<void> refresh();

  Future<Task> createAfter({
    required String title,
    required String status,
    int? afterTaskId,
  });

  /// When the list is empty, optionally create a server seed. Return null to
  /// keep a local unsaved seed row only.
  Future<Task?> ensureSeed();

  Future<void> delete(Task task);

  /// Return false to cancel delete (e.g. user dismissed confirm).
  Future<bool> confirmDelete(Task task) async => true;

  Future<void> updateTitle(Task task, String title);

  Future<void> updateListTitle(String title) async {}

  Future<void> moveInZone({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
  });

  Future<void> reorder(List<int> orderedIds);

  Future<void> markAll({required bool done});

  bool acceptsDrag(TaskDragPayload payload) =>
      payload.sourceListId == dragGroupId;
}
