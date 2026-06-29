import '../models/block.dart';
import 'api_service.dart';

class BlockService {
  BlockService(this._api);

  final ApiService _api;

  Future<Block> getBlock(int id) async {
    final data = await _api.get('/blocks/$id') as Map<String, dynamic>;
    return Block.fromJson(data);
  }

  Future<List<Block>> listForFile(
    int fileId, {
    bool includeArchived = false,
  }) async {
    final path = includeArchived
        ? '/files/$fileId/blocks?include_archived=true'
        : '/files/$fileId/blocks';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => Block.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
  }

  Future<Block> createBlock({
    required int fileId,
    required String type,
    Map<String, dynamic>? content,
    int? orderIndex,
  }) async {
    final data =
        await _api.post('/blocks', {
              'file_id': fileId,
              'type': type,
              'content': content ?? {},
              if (orderIndex != null) 'order_index': orderIndex,
            })
            as Map<String, dynamic>;
    return Block.fromJson(data);
  }

  Future<Block> updateBlock(int id, Map<String, dynamic> patch) async {
    final data = await _api.patch('/blocks/$id', patch) as Map<String, dynamic>;
    return Block.fromJson(data);
  }

  Future<void> deleteBlock(int id) async {
    await _api.delete('/blocks/$id');
  }
}
