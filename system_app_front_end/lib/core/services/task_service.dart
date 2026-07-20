import '../models/task.dart';
import 'api_service.dart';

class TaskService {
  TaskService(this._api);

  final ApiService _api;

  Future<List<Task>> listForBlock(int blockId) async {
    final data = await _api.get('/blocks/$blockId/tasks') as List<dynamic>;
    return data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Task>> listByView(String viewType) async {
    final data = await _api.get('/tasks/view/$viewType') as List<dynamic>;
    return data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Task> createTask({
    required int blockId,
    required String title,
    String status = 'active',
  }) async {
    final data = await _api.post('/tasks', {
      'block_id': blockId,
      'title': title,
      'status': status,
    }) as Map<String, dynamic>;
    return Task.fromJson(data);
  }

  Future<Map<String, dynamic>> updateTaskRaw(
    int id,
    Map<String, dynamic> patch,
  ) async {
    return await _api.patch('/tasks/$id', patch) as Map<String, dynamic>;
  }

  Future<Task> updateTask(int id, Map<String, dynamic> patch) async {
    final data = await updateTaskRaw(id, patch);
    return Task.fromJson(data);
  }

  Future<void> deleteTask(int id) async {
    await _api.delete('/tasks/$id');
  }

  Future<List<Task>> reorderTasksInListBlock(
    int blockId,
    List<int> taskIds,
  ) async {
    final data = await _api.post('/blocks/$blockId/tasks/reorder', {
      'task_ids': taskIds,
    }) as List<dynamic>;
    return data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<({
    Task task,
    List<Task> targetTasks,
    List<Task> sourceTasks,
    int? sourceBlockId,
  })> moveTaskToListBlock({
    required int blockId,
    required int taskId,
    required int insertIndex,
    required bool targetDone,
  }) async {
    final data = await _api.post('/blocks/$blockId/tasks/move', {
      'task_id': taskId,
      'insert_index': insertIndex,
      'target_done': targetDone,
    }) as Map<String, dynamic>;
    return (
      task: Task.fromJson(data['task'] as Map<String, dynamic>),
      targetTasks: (data['target_tasks'] as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceTasks: (data['source_tasks'] as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceBlockId: data['source_block_id'] as int?,
    );
  }
}
