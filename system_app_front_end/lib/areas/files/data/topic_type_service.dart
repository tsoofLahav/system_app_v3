import '../../../core/services/api_service.dart';
import './topic_type.dart';

class TopicTypeService {
  TopicTypeService(this._api);

  final ApiService _api;

  Future<List<TopicType>> list({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/topic-types?workspace_id=$workspaceId'
        : '/topic-types';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => TopicType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TopicType> create({
    required int workspaceId,
    required String name,
    required String nameHe,
  }) async {
    final data =
        await _api.post('/topic-types', {
              'workspace_id': workspaceId,
              'name': name,
              'name_he': nameHe,
            })
            as Map<String, dynamic>;
    return TopicType.fromJson(data);
  }

  Future<TopicType> update(int id, Map<String, dynamic> body) async {
    final data =
        await _api.patch('/topic-types/$id', body) as Map<String, dynamic>;
    return TopicType.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _api.delete('/topic-types/$id');
  }
}
