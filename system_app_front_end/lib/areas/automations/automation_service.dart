import './automation.dart';
import '../../core/services/api_service.dart';

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
    String icon = '',
    int? barSlot,
  }) async {
    final data =
        await _api.post('/automations', {
              'workspace_id': workspaceId,
              'name': name,
              'prompt': prompt,
              'apply_mode': applyMode,
              'trigger': trigger,
              'scope': scope ?? {},
              'icon': icon,
              'bar_slot': ?barSlot,
              'schedule': ?schedule,
            })
            as Map<String, dynamic>;
    return Automation.fromJson(data);
  }

  Future<Automation> update(int id, Map<String, dynamic> body) async {
    final data =
        await _api.patch('/automations/$id', body) as Map<String, dynamic>;
    return Automation.fromJson(data);
  }

  /// Replaces the AI bar: the first six ids take slots 1..6, the rest unpin.
  Future<List<Automation>> setBarOrder({
    required int workspaceId,
    required List<int> orderedIds,
  }) async {
    final data =
        await _api.put('/automations/bar-order', {
              'workspace_id': workspaceId,
              'ordered_ids': orderedIds,
            })
            as List<dynamic>;
    return data
        .map((e) => Automation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> delete(int id) async {
    await _api.delete('/automations/$id');
  }

  /// [scope] and [hints] carry what is open when the user fires the action;
  /// omitting them leaves the run on the scope stored with the record.
  Future<Map<String, dynamic>> run(
    int id, {
    Map<String, dynamic>? scope,
    Map<String, dynamic>? hints,
  }) async {
    final data =
        await _api.post('/automations/$id/run', {
              'scope': ?scope,
              'hints': ?hints,
            })
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
