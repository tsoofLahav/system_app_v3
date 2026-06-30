import 'api_service.dart';

class AutomationCompanionService {
  AutomationCompanionService(this._api);

  final ApiService _api;

  Future<void> complete(int companionTaskId) async {
    await _api.post('/automation_companion_tasks/$companionTaskId/complete', {});
  }
}
