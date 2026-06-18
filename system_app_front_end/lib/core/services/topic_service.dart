import '../models/topic.dart';
import 'api_service.dart';

class TopicService {
  TopicService(this._api);

  final ApiService _api;

  Future<List<Topic>> listTopics({bool includeArchived = false}) async {
    final data =
        await _api.get(
              includeArchived ? '/topics?include_archived=true' : '/topics',
            )
            as List<dynamic>;
    return data.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Topic> createTopic({
    required String name,
    required String type,
    String? icon,
    String? color,
  }) async {
    final data =
        await _api.post('/topics', {
              'name': name,
              'type': type,
              if (icon != null) 'icon': icon,
              if (color != null) 'color': color,
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
