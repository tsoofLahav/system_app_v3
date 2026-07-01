import '../models/automation_definition.dart';
import 'api_service.dart';

class AutomationDefinitionService {
  AutomationDefinitionService(this._api);

  final ApiService _api;

  Future<List<AutomationDefinition>> list() async {
    final data = await _api.get('/automation_definitions') as List<dynamic>;
    return data
        .map(
          (entry) => AutomationDefinition.fromJson(
            entry as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<AutomationDefinition> getByKey(String key) async {
    final data =
        await _api.get('/automation_definitions/$key') as Map<String, dynamic>;
    return AutomationDefinition.fromJson(data);
  }
}
