import '../models/part.dart';
import 'api_service.dart';

class PartService {
  PartService(this._api);

  final ApiService _api;

  Future<List<Part>> listForTopic(int topicId) async {
    final data = await _api.get('/topics/$topicId/parts') as List<dynamic>;
    return data
        .map((e) => Part.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Future<List<int>> partIdsInFile(int fileId) async {
    final data = await _api.get('/files/$fileId/part-ids') as List<dynamic>;
    return data.map((e) => e as int).toList();
  }

  Future<Map<String, dynamic>> placePartInFile({
    required int fileId,
    int? partId,
    String? name,
    int? insertAfterBlockId,
    int? insertIndex,
  }) async {
    return await _api.post('/files/$fileId/parts', {
          if (partId != null) 'part_id': partId,
          if (name != null) 'name': name,
          if (insertAfterBlockId != null)
            'insert_after_block_id': insertAfterBlockId,
          if (insertIndex != null) 'insert_index': insertIndex,
        })
        as Map<String, dynamic>;
  }

  Future<Part> updatePart(int partId, Map<String, dynamic> patch) async {
    final data =
        await _api.patch('/parts/$partId', patch) as Map<String, dynamic>;
    return Part.fromJson(data);
  }

  Future<void> archivePart(int partId) async {
    await _api.delete('/parts/$partId');
  }
}
