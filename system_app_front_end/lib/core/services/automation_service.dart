import '../models/automation_rule.dart';
import 'api_service.dart';

class AutomationService {
  AutomationService(this._api);

  final ApiService _api;

  Future<List<AutomationRule>> listRules() async {
    final data = await _api.get('/automation_rules') as List<dynamic>;
    return data
        .map((e) => AutomationRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AutomationRule> createRule(Map<String, dynamic> body) async {
    final data =
        await _api.post('/automation_rules', body) as Map<String, dynamic>;
    return AutomationRule.fromJson(data);
  }

  Future<AutomationRule> updateRule(int id, Map<String, dynamic> patch) async {
    final data =
        await _api.patch('/automation_rules/$id', patch)
            as Map<String, dynamic>;
    return AutomationRule.fromJson(data);
  }

  Future<void> runRule(int id) async {
    await _api.post('/automation_rules/$id/run', {});
  }
}
