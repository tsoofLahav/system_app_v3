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
}
