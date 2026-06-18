class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.key,
    required this.name,
    required this.actionType,
    required this.triggerType,
    required this.schedule,
    required this.timezone,
    required this.params,
    required this.enabled,
    this.lastRunAt,
    this.nextRunAt,
  });

  final int id;
  final String key;
  final String name;
  final String actionType;
  final String triggerType;
  final String schedule;
  final String timezone;
  final Map<String, dynamic> params;
  final bool enabled;
  final String? lastRunAt;
  final String? nextRunAt;

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    final rawParams = json['params'];
    return AutomationRule(
      id: json['id'] as int,
      key: json['key'] as String,
      name: json['name'] as String,
      actionType: json['action_type'] as String,
      triggerType: json['trigger_type'] as String? ?? 'schedule',
      schedule: json['schedule'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
      params: rawParams is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawParams)
          : <String, dynamic>{},
      enabled: json['enabled'] as bool? ?? true,
      lastRunAt: json['last_run_at'] as String?,
      nextRunAt: json['next_run_at'] as String?,
    );
  }

  Map<String, dynamic> toPatch() => {
    'key': key,
    'name': name,
    'action_type': actionType,
    'trigger_type': triggerType,
    'schedule': schedule,
    'timezone': timezone,
    'params': params,
    'enabled': enabled,
  };
}
