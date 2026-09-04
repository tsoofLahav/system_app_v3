import '../../core/services/api_service.dart';
import './automation.dart';
import './schedule_format.dart';

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
    String timezone = AutomationSchedule.defaultTimezone,
    bool enabled = true,
    String kind = 'standard',
    int? viewId,
    String? sectionKey,
    int? windowDurationMinutes,
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
              'kind': kind,
              'view_id': ?viewId,
              'section_key': ?sectionKey,
              'window_duration_minutes': ?windowDurationMinutes,
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
  Future<Map<String, dynamic>> run(
    int id, {
    Map<String, dynamic>? userInput,
  }) async {
    final data = await _api.post('/automations/$id/run', {
          if (userInput != null) 'user_input': userInput,
        })
        as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<List<Automation>> pendingClears({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/automations/pending-clears?workspace_id=$workspaceId'
        : '/automations/pending-clears';
    final data = await _api.get(path) as List<dynamic>;
    return data
        .map((e) => Automation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> submitInput(
    int id,
    Map<String, dynamic> body,
  ) async {
    final data =
        await _api.post('/automations/$id/submit-input', body)
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> clearLeftovers(
    int id, {
    required String disposition,
  }) async {
    final data =
        await _api.post('/automations/$id/clear-leftovers', {
          'disposition': disposition,
        })
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> reviewStatus(int id) async {
    final data =
        await _api.get('/automations/$id/review-status')
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> completeReview(int id) async {
    final data =
        await _api.post('/automations/$id/complete-review', {})
            as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> inputTopics(int id) async {
    final data = await _api.get('/automations/$id/input-topics') as List<dynamic>;
    return [
      for (final item in data)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
}
