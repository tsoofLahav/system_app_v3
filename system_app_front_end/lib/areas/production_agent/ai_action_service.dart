import '../../core/services/api_service.dart';
import './ai_action.dart';

class AiActionService {
  AiActionService(this._api);

  final ApiService _api;

  Future<List<AiAction>> list({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/ai-actions?workspace_id=$workspaceId'
        : '/ai-actions';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => AiAction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AiAction> create({
    required int workspaceId,
    required String name,
    required String nameHe,
    required String prompt,
    required String applyMode,
    String icon = '',
    int? barSlot,
    int? topicTypeId,
    int? topicId,
  }) async {
    final data =
        await _api.post('/ai-actions', {
              'workspace_id': workspaceId,
              'name': name,
              'name_he': nameHe,
              'prompt': prompt,
              'apply_mode': applyMode,
              'icon': icon,
              'bar_slot': ?barSlot,
              'topic_type_id': ?topicTypeId,
              'topic_id': ?topicId,
            })
            as Map<String, dynamic>;
    return AiAction.fromJson(data);
  }

  Future<AiAction> update(int id, Map<String, dynamic> body) async {
    final data =
        await _api.patch('/ai-actions/$id', body) as Map<String, dynamic>;
    return AiAction.fromJson(data);
  }

  /// Replaces the AI bar: the first six ids take slots 1..6, the rest unpin.
  Future<List<AiAction>> setBarOrder({
    required int workspaceId,
    required List<int> orderedIds,
  }) async {
    final data =
        await _api.put('/ai-actions/bar-order', {
              'workspace_id': workspaceId,
              'ordered_ids': orderedIds,
            })
            as List<dynamic>;
    return data.map((e) => AiAction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> delete(int id) async {
    await _api.delete('/ai-actions/$id');
  }

  /// [scope] and [hints] carry what is open when the user fires the action.
  Future<Map<String, dynamic>> run(
    int id, {
    Map<String, dynamic>? scope,
    Map<String, dynamic>? hints,
  }) async {
    final data =
        await _api.post('/ai-actions/$id/run', {
              'scope': ?scope,
              'hints': ?hints,
            })
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
