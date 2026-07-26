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

  Future<ObjectEmbed> createObject({
    required int fileId,
    required String type,
    String? title,
    String? body,
    int? index,
    int? offset,
    String? documentBody,
  }) async {
    final data =
        await _api.post('/files/$fileId/objects', {
              'type': type,
              if (title != null) 'title': title,
              if (body != null) 'body': body,
              if (index != null) 'index': index,
              if (offset != null) 'offset': offset,
              if (documentBody != null) 'document_body': documentBody,
            })
            as Map<String, dynamic>;
    return ObjectEmbed.fromJson(data);
  }

  Future<void> deleteEmbed(int objectId) async {
    await _api.delete('/objects/$objectId');
  }

  Future<List<Map<String, dynamic>>> listLinks(int objectId) async {
    return (await _api.get('/objects/$objectId/links') as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createLink(
    int objectId, {
    required String targetType,
    required int targetId,
    String? label,
  }) async {
    return await _api.post('/objects/$objectId/links', {
          'target_type': targetType,
          'target_id': targetId,
          if (label != null) 'label': label,
        })
        as Map<String, dynamic>;
  }

  Future<void> deleteLink(int objectId, int linkId) async {
    await _api.delete('/objects/$objectId/links/$linkId');
  }
}
