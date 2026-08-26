import '../../../core/app_state.dart';
import '../data/task.dart';
import '../tasks/task_list_bridge.dart';
import '../tasks/task_zones.dart';

/// Persistence for one view frame's task list (section or topic bucket).
class ViewFrameTaskListBridge extends TaskListBridge {
  ViewFrameTaskListBridge({
    required this.state,
    required this.frameTasks,
    required this.sectionName,
    required this.sectionFlag,
    required this.topicKey,
    this.confirmDeleteFn,
  });

  final AppState state;
  List<Task> frameTasks;
  String? sectionName;
  String? sectionFlag;
  String? topicKey;
  Future<bool> Function(Task task)? confirmDeleteFn;

  @override
  List<Task> get remoteTasks => [
        for (final task in frameTasks) state.hydrateTask(task),
      ];

  @override
  int get dragGroupId => state.selectedView?.id ?? 0;

  @override
  bool get showListTitle => false;

  @override
  bool get sortRemoteByListOrder => false;

  @override
  String get listTitle => '';

  @override
  Future<void> refresh() =>
      state.refreshOpenTaskSurfaces(notify: true);

  @override
  Future<Task> createAfter({
    required String title,
    required String status,
    int? afterTaskId,
  }) {
    return state.createTaskInView(
      title: title,
      status: status,
      afterTaskId: afterTaskId,
      sectionName: sectionName,
      sectionFlag: sectionFlag,
      topicKey: topicKey,
      notify: false,
    );
  }

  @override
  Future<Task?> ensureSeed() async {
    // Keep a local unsaved seed row only — do not create orphans in every
    // empty section/topic frame when the view opens.
    return null;
  }

  @override
  Future<void> delete(Task task) =>
      state.deleteTask(task, notify: false);

  @override
  Future<bool> confirmDelete(Task task) async {
    if (confirmDeleteFn != null) return confirmDeleteFn!(task);
    return true;
  }

  @override
  Future<void> updateTitle(Task task, String title) =>
      state.updateTaskTitle(task, title, notify: false);

  @override
  Future<void> moveInZone({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    final zones = TaskZones.fromOrdered(remoteTasks);
    final next = zones.moved(
      taskId: task.id,
      targetDone: targetDone,
      indexInZone: insertIndexInZone,
    );
    if (task.isDone != targetDone) {
      await state.toggleTaskStatus(task, notify: false);
    }
    await _persistFrameOrder(next.orderedIds);
  }

  @override
  Future<void> reorder(List<int> orderedIds) =>
      _persistFrameOrder(orderedIds);

  @override
  Future<void> markAll({required bool done}) async {
    for (final task in List<Task>.of(remoteTasks)) {
      if (task.isDone == done) continue;
      await state.toggleTaskStatus(task, notify: false);
    }
  }

  Future<void> _persistFrameOrder(List<int> frameOrderedIds) async {
    if (state.selectedView == null) return;
    final byTopic = state.viewDisplayMode == ViewDisplayMode.byTopic;
    final frameIndex = {
      for (var i = 0; i < frameOrderedIds.length; i++) frameOrderedIds[i]: i,
    };
    final memberships = <Map<String, dynamic>>[];
    for (final m in state.viewMemberships) {
      final id = m.taskId;
      final at = id == null ? null : frameIndex[id];
      memberships.add({
        ...m.toReplaceJson(),
        if (!byTopic && at != null) 'order_index': at,
        if (byTopic && at != null) 'topic_order_index': at,
      });
    }
    await state.reorderViewMemberships(memberships, notify: false);
  }
}
