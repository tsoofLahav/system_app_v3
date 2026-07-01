import '../models/automation_companion_link.dart';
import 'api_service.dart';

class AutomationCompanionService {
  AutomationCompanionService(this._api);

  final ApiService _api;

  Future<List<AutomationCompanionLink>> listPendingForTask(int taskId) async {
    final data =
        await _api.get('/automation_companion_tasks/by-task/$taskId/pending')
            as List<dynamic>;
    return data
        .map(
          (entry) => AutomationCompanionLink.fromJson(
            entry as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> complete(int companionTaskId) async {
    final data = await _api.post(
      '/automation_companion_tasks/$companionTaskId/complete',
      {},
    );
    return Map<String, dynamic>.from(data as Map);
  }
}
