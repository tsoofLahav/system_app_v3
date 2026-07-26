import '../models/automation.dart';
import 'api_service.dart';

class AutomationService {
  AutomationService(this._api);

  final ApiService _api;

  Future<List<Automation>> list({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/automations?workspace_id=$workspaceId'
        : '/automations';
    final data = await _api.get(path) as List<dynamic>;
    return data
        .map((e) => Automation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Automation> create({
    required int workspaceId,
    required String name,
    required String prompt,
    required String applyMode,
    required Map<String, dynamic> trigger,
    Map<String, dynamic>? scope,
    String? schedule,
  }) async {
    final data =
        await _api.post('/automations', {
              'workspace_id': workspaceId,
              'name': name,
              'prompt': prompt,
              'apply_mode': applyMode,
              'trigger': trigger,
              'scope': scope ?? {},
              if (schedule != null) 'schedule': schedule,
            })
            as Map<String, dynamic>;
    return Automation.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _api.delete('/automations/$id');
  }

  Future<Map<String, dynamic>> run(int id) async {
    final data =
        await _api.post('/automations/$id/run', {}) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
