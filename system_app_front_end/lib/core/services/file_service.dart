import '../models/app_file.dart';
import '../models/archive_files_page.dart';
import 'api_service.dart';

class FileService {
  FileService(this._api);

  final ApiService _api;

  Future<List<AppFile>> listForTopic(
    int topicId, {
    bool includeArchived = false,
  }) async {
    final path = includeArchived
        ? '/topics/$topicId/files?include_archived=true'
        : '/topics/$topicId/files';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => AppFile.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
  }

  Future<ArchiveFilesPage> listArchiveForTopic(
    int topicId, {
    int limit = 24,
    int offset = 0,
    String? query,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await _api.get(
      '/topics/$topicId/archive/files?$queryString',
    ) as Map<String, dynamic>;
    return ArchiveFilesPage.fromJson(data);
  }

  Future<AppFile> createFile({
    required int topicId,
    required String name,
    required String type,
    int? orderIndex,
    bool? isMain,
  }) async {
    final data =
        await _api.post('/files', {
              'topic_id': topicId,
              'name': name,
              'type': type,
              if (orderIndex != null) 'order_index': orderIndex,
              if (isMain != null) 'is_main': isMain,
            })
            as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<void> deleteFile(int id) async {
    await _api.delete('/files/$id');
  }

  Future<AppFile> updateFile(int id, Map<String, dynamic> patch) async {
    final data = await _api.patch('/files/$id', patch) as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }
}
