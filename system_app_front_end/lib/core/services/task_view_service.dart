import '../models/task_view_membership.dart';
import '../models/view_section.dart';
import '../models/view_section_flags.dart';
import 'api_service.dart';

class TaskViewService {
  TaskViewService(this._api);

  final ApiService _api;

  Future<List<TaskViewMembership>> listAll() async {
    final data = await _api.get('/task_views') as List<dynamic>;
    return data
        .map((e) => TaskViewMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ViewSection>> listSectionsForView(String viewType) async {
    final data =
        await _api.get('/task_views/sections/$viewType') as List<dynamic>;
    return data
        .map((e) => ViewSection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ViewSection> createSection({
    required String viewType,
    required String name,
  }) async {
    final data = await _api.post('/task_views', {
      'view_type': viewType,
      'section_name': name,
    }) as Map<String, dynamic>;
    return ViewSection.fromJson(data);
  }

  Future<TaskViewMembership> createMembership({
    required int taskId,
    required String viewType,
    String? sectionName,
  }) async {
    final data = await _api.post('/task_views', {
      'task_id': taskId,
      'view_type': viewType,
      if (sectionName != null) 'section_name': sectionName,
    }) as Map<String, dynamic>;
    return TaskViewMembership.fromJson(data);
  }

  Future<ViewSection> updateSectionImportance(
    int id, {
    required bool important,
  }) async {
    final data = await _api.patch('/task_views/$id', {
      'section_flag': important ? ViewSectionFlags.important : null,
    }) as Map<String, dynamic>;
    return ViewSection.fromJson(data);
  }

  Future<TaskViewMembership> update(
    int id, {
    String? sectionName,
    bool clearSection = false,
  }) async {
    final body = <String, dynamic>{};
    if (clearSection) {
      body['section_name'] = null;
    } else if (sectionName != null) {
      body['section_name'] = sectionName;
    }
    final data = await _api.patch('/task_views/$id', body) as Map<String, dynamic>;
    return TaskViewMembership.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _api.delete('/task_views/$id');
  }

  Future<void> updateOrderIndex(int id, int orderIndex) async {
    await _api.patch('/task_views/$id', {'order_index': orderIndex});
  }
}
