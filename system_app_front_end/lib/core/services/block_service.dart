import '../models/block.dart';
import 'api_service.dart';

class BlockService {
  BlockService(this._api);

  final ApiService _api;

  Future<List<Block>> listForFile(int fileId) async {
    final data = await _api.get('/files/$fileId/blocks') as List<dynamic>;
    return data.map((e) => Block.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
  }

  Future<Block> createBlock({
    required int fileId,
    required String type,
    Map<String, dynamic>? content,
    int? orderIndex,
  }) async {
    final data = await _api.post('/blocks', {
      'file_id': fileId,
      'type': type,
      'content': content ?? {},
      if (orderIndex != null) 'order_index': orderIndex,
    }) as Map<String, dynamic>;
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
