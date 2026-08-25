import './task.dart';
import '../../../core/services/api_service.dart';

class TaskService {
  TaskService(this._api);

  final ApiService _api;

  Future<List<Task>> listForTaskList(int taskListId) async {
    final data =
        await _api.get('/task-lists/$taskListId/tasks') as List<dynamic>;
    return data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Task> createInList({
    required int taskListId,
    required String title,
    String status = 'active',
    int? listOrderIndex,
  }) async {
    final data = await _api.post('/task-lists/$taskListId/tasks', {
      'title': title,
      'status': status,
      if (listOrderIndex != null) 'list_order_index': listOrderIndex,
    }) as Map<String, dynamic>;
    return Task.fromJson(data);
  }

  Future<Task> updateTask(int id, Map<String, dynamic> patch) async {
    final data = await _api.patch('/tasks/$id', patch) as Map<String, dynamic>;
    return Task.fromJson(data);
  }

  Future<void> deleteTask(int id) async {
    await _api.delete('/tasks/$id');
  }

  Future<List<Task>> reorderInList(int taskListId, List<int> taskIds) async {
    final data = await _api.put('/task-lists/$taskListId/tasks/order', {
      'ordered_task_ids': taskIds,
    }) as List<dynamic>;
    return data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Same-list or cross-list move into an Active/Done zone slot.
  Future<void> moveToListZone({
    required int taskId,
    required int targetTaskListId,
    required int insertIndexInZone,
    required bool targetDone,
  }) async {
    await _api.post('/tasks/$taskId/move', {
      'target_task_list_id': targetTaskListId,
      'insert_index_in_zone': insertIndexInZone,
      'target_done': targetDone,
    });
  }

  Future<List<Map<String, dynamic>>> getTaskMemberships(int taskId) async {
    return (await _api.get('/tasks/$taskId/memberships') as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> replaceTaskMemberships(
    int taskId,
    List<Map<String, dynamic>> memberships,
  ) async {
    return (await _api.put('/tasks/$taskId/memberships', {
          'memberships': memberships,
        }) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createDescriptionLink(
    int taskId, {
    required int targetObjectId,
    required Map<String, dynamic> anchor,
    String? label,
  }) async {
    return await _api.post('/tasks/$taskId/links', {
          'kind': 'description',
          'target_object_id': targetObjectId,
          'anchor': anchor,
          if (label != null) 'label': label,
        })
        as Map<String, dynamic>;
  }
}
