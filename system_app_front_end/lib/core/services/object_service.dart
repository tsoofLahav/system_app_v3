import '../models/object_embed.dart';
import 'api_service.dart';

class ObjectService {
  ObjectService(this._api);

  final ApiService _api;

  Future<List<ObjectEmbed>> listForFile(int fileId) async {
    final data = await _api.get('/files/$fileId/objects') as List<dynamic>;
    return data
        .map((e) => ObjectEmbed.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ObjectEmbed> createTaskEmbed({
    required int fileId,
    required String title,
    int? line,
  }) async {
    final data =
        await _api.post('/files/$fileId/objects', {
              'type': 'task',
              'title': title,
              if (line != null) 'line': line,
            })
            as Map<String, dynamic>;
    return ObjectEmbed.fromJson(data);
  }

  Future<void> deleteEmbed(int objectId) async {
    await _api.delete('/objects/$objectId');
  }
}
