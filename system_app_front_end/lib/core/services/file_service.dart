import '../models/app_file.dart';
import 'api_service.dart';

class FileService {
  FileService(this._api);

  final ApiService _api;

  Future<List<AppFile>> listFilesForTopic(int topicId) async {
    final data = await _api.get('/topics/$topicId/files') as List<dynamic>;
    return data.map((e) => AppFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppFile> getFile(int id) async {
    final data = await _api.get('/files/$id') as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<AppFile> createFile({
    required int topicId,
    required String name,
    String body = '',
    bool isEssence = false,
    int? orderIndex,
    Map<String, dynamic>? meta,
  }) async {
    final data =
        await _api.post('/files', {
              'topic_id': topicId,
              'name': name,
              'body': body,
              'is_essence': isEssence,
              if (orderIndex != null) 'order_index': orderIndex,
              if (meta != null) 'meta': meta,
            })
            as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<AppFile> updateFile(int id, Map<String, dynamic> body) async {
    final data = await _api.patch('/files/$id', body) as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<void> deleteFile(int id) async {
    await _api.delete('/files/$id');
  }

  Future<List<AppFile>> listArchivedForTopic(int topicId) async {
    final data =
        await _api.get('/topics/$topicId/archive/files') as List<dynamic>;
    return data.map((e) => AppFile.fromJson(e as Map<String, dynamic>)).toList();
  }
}
