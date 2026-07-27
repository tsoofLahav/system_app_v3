import '../../core/services/api_service.dart';

class AgentService {
  AgentService(this._api);

  final ApiService _api;

  Future<Map<String, dynamic>> run({
    required String prompt,
    required int workspaceId,
    Map<String, dynamic>? scope,
    String applyMode = 'review',
  }) async {
    final data =
        await _api.post('/agent/run', {
              'prompt': prompt,
              'workspace_id': workspaceId,
              'scope': scope ?? {},
              'apply_mode': applyMode,
            })
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
