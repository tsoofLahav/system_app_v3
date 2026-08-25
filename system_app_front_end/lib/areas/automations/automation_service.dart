import '../../core/services/api_service.dart';
import './automation.dart';

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
    required String nameHe,
    required Map<String, dynamic> trigger,
    required Map<String, dynamic> scope,
    required List<Map<String, dynamic>> steps,
    String? schedule,
    String timezone = 'UTC',
    bool enabled = true,
  }) async {
    final data =
        await _api.post('/automations', {
              'workspace_id': workspaceId,
              'name': name,
              'name_he': nameHe,
              'trigger': trigger,
              'scope': scope,
              'steps': steps,
              'schedule': ?schedule,
              'timezone': timezone,
              'enabled': enabled,
            })
            as Map<String, dynamic>;
    return Automation.fromJson(data);
  }

  Future<Automation> update(int id, Map<String, dynamic> body) async {
    final data =
        await _api.patch('/automations/$id', body) as Map<String, dynamic>;
    return Automation.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _api.delete('/automations/$id');
  }

  /// Run it now on its own stored scope — the same thing the clock would do.
  Future<Map<String, dynamic>> run(int id) async {
    final data = await _api.post('/automations/$id/run', {})
        as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
