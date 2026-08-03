import './app_view.dart';
import './task.dart';
import '../../../core/services/api_service.dart';

class ViewService {
  ViewService(this._api);

  final ApiService _api;

  Future<List<AppView>> listViews({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/views?workspace_id=$workspaceId'
        : '/views';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => AppView.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppView> createView({
    required int workspaceId,
    required String name,
    Map<String, dynamic>? layoutConfig,
  }) async {
    final data =
        await _api.post('/views', {
              'workspace_id': workspaceId,
              'name': name,
              if (layoutConfig != null) 'layout_config': layoutConfig,
            })
            as Map<String, dynamic>;
    return AppView.fromJson(data);
  }

  Future<AppView> updateView(
    int viewId, {
    String? name,
    Map<String, dynamic>? layoutConfig,
  }) async {
    final data = await _api.patch('/views/$viewId', {
      if (name != null) 'name': name,
      if (layoutConfig != null) 'layout_config': layoutConfig,
    }) as Map<String, dynamic>;
    return AppView.fromJson(data);
  }

  Future<List<ViewMembership>> listMemberships(int viewId) async {
    final data =
        await _api.get('/views/$viewId/memberships') as List<dynamic>;
    return data
        .map((e) => ViewMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ViewMembership>> replaceMemberships(
    int viewId,
    List<Map<String, dynamic>> memberships,
  ) async {
    final data =
        await _api.put('/views/$viewId/memberships', {
              'memberships': memberships,
            })
            as List<dynamic>;
    return data
        .map((e) => ViewMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Task> createTaskInView(
    int viewId, {
    String title = '',
    String status = 'active',
    int? afterTaskId,
    int? taskListId,
    String? sectionName,
    String? sectionFlag,
    String? topicKey,
  }) async {
    final data = await _api.post('/views/$viewId/tasks', {
      'title': title,
      'status': status,
      if (afterTaskId != null) 'after_task_id': afterTaskId,
      if (taskListId != null) 'task_list_id': taskListId,
      if (sectionName != null) 'section_name': sectionName,
      if (sectionFlag != null) 'section_flag': sectionFlag,
      if (topicKey != null) 'topic_key': topicKey,
    }) as Map<String, dynamic>;
    return Task.fromJson(data);
  }
}
