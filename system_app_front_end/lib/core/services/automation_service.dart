import '../models/automation_rule.dart';
import '../models/automation_run.dart';
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

  Future<AutomationRun> runRule(int id) async {
    final data =
        await _api.post('/automation_rules/$id/run', {})
            as Map<String, dynamic>;
    return AutomationRun.fromJson(data['run'] as Map<String, dynamic>);
  }

  Future<AutomationRun> getRun(int id) async {
    final data = await _api.get('/automation_runs/$id') as Map<String, dynamic>;
    return AutomationRun.fromJson(data);
  }

  Future<List<AutomationRun>> listActiveRuns({int? ruleId}) async {
    final query = StringBuffer('/automation_runs?status=queued,running&limit=20');
    if (ruleId != null) {
      query.write('&rule_id=$ruleId');
    }
    final data = await _api.get(query.toString()) as List<dynamic>;
    return data
        .map((e) => AutomationRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
