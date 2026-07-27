import './topic.dart';
import '../../../core/services/api_service.dart';

class TopicService {
  TopicService(this._api);

  final ApiService _api;

  Future<List<Topic>> listTopics({int? workspaceId, bool includeArchived = false}) async {
    final query = StringBuffer('/topics');
    final params = <String>[];
    if (workspaceId != null) params.add('workspace_id=$workspaceId');
    if (includeArchived) params.add('include_archived=true');
    if (params.isNotEmpty) query.write('?${params.join('&')}');
    final data = await _api.get(query.toString()) as List<dynamic>;
    return data.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Topic> createTopic({
    required String name,
    required int workspaceId,
    String? icon,
    String? color,
    List<int>? tagIds,
  }) async {
    final data =
        await _api.post('/topics', {
              'name': name,
              'workspace_id': workspaceId,
              if (icon != null) 'icon': icon,
              if (color != null) 'color': color,
              if (tagIds != null) 'tag_ids': tagIds,
            })
            as Map<String, dynamic>;
    return Topic.fromJson(data);
  }

  Future<void> deleteTopic(int id) async {
    await _api.delete('/topics/$id');
  }

  Future<Topic> updateTopic(int id, Map<String, dynamic> body) async {
    final data = await _api.patch('/topics/$id', body) as Map<String, dynamic>;
    return Topic.fromJson(data);
  }
}
