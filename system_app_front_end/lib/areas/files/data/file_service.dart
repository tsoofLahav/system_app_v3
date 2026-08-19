import './app_file.dart';
import '../../../core/models/archive_files_page.dart';
import '../../../core/services/api_service.dart';

class FileService {
  FileService(this._api);

  final ApiService _api;

  Future<List<AppFile>> listFilesForTopic(int topicId) async {
    final data = await _api.get('/topics/$topicId/files') as List<dynamic>;
    return data.map((e) => AppFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AppFile>> listAllFiles() async {
    final data = await _api.get('/files') as List<dynamic>;
    return data.map((e) => AppFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppFile> getFile(int id) async {
    final data = await _api.get('/files/$id') as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<AppFile> createFile({
    required int topicId,
    required String name,
    String documentJson = '',
    int? orderIndex,
    Map<String, dynamic>? meta,
  }) async {
    final data =
        await _api.post('/files', {
              'topic_id': topicId,
              'name': name,
              'document_json': documentJson,
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

  Future<AppFile> applyAgentText(
    int id, {
    required String documentJson,
    Map<String, dynamic>? objectUpdates,
    String? tool,
  }) async {
    final data = await _api.post('/files/$id/apply-agent-text', {
          'document_json': documentJson,
          if (objectUpdates != null) 'object_updates': objectUpdates,
          if (tool != null) 'tool': tool,
        }) as Map<String, dynamic>;
    return AppFile.fromJson(data);
  }

  Future<void> deleteFile(int id) async {
    await _api.delete('/files/$id');
  }

  Future<ArchiveFilesPage> listArchivedForTopic(
    int topicId, {
    int limit = 24,
    int offset = 0,
    String? query,
  }) async {
    final params = <String>[
      'limit=$limit',
      'offset=$offset',
      if (query != null && query.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(query.trim())}',
    ];
    final data = await _api.get(
      '/topics/$topicId/archive/files?${params.join('&')}',
    );
    if (data is List) {
      final files = data
          .map((e) => AppFile.fromJson(e as Map<String, dynamic>))
          .toList();
      return ArchiveFilesPage(
        files: files,
        total: files.length,
        hasMore: false,
        headerTextsByFileId: const {},
      );
    }
    return ArchiveFilesPage.fromJson(data as Map<String, dynamic>);
  }

  Future<String> agentTextForFile(int id) async {
    final data = await _api.get('/files/$id/agent-text') as Map<String, dynamic>;
    return data['agent_text'] as String? ?? '';
  }
}
