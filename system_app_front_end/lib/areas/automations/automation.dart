import '../production_agent/agent_run_defaults.dart';

class Automation {
  const Automation({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.prompt,
    required this.applyMode,
    this.trigger = const {},
    this.scope = const {},
    this.schedule,
    this.timezone = 'UTC',
    this.enabled = true,
  });

  final int id;
  final int workspaceId;
  final String name;
  final String prompt;
  final String applyMode;
  final Map<String, dynamic> trigger;
  final Map<String, dynamic> scope;
  final String? schedule;
  final String timezone;
  final bool enabled;

  bool get isManual => trigger['type'] == 'manual';
  bool get isScheduled =>
      trigger['type'] == 'schedule' || (schedule != null && schedule!.isNotEmpty);

  factory Automation.fromJson(Map<String, dynamic> json) {
    final trigger = json['trigger'];
    final scope = json['scope'];
    return Automation(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      prompt: json['prompt'] as String? ?? '',
      applyMode:
          json['apply_mode'] as String? ?? defaultAutomationApplyMode,
      trigger: trigger is Map<String, dynamic>
          ? Map<String, dynamic>.from(trigger)
          : const {},
      scope: scope is Map<String, dynamic>
          ? Map<String, dynamic>.from(scope)
          : const {},
      schedule: json['schedule'] as String?,
      timezone: json['timezone'] as String? ?? 'UTC',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson({required int workspaceId}) => {
    'workspace_id': workspaceId,
    'name': name,
    'prompt': prompt,
    'apply_mode': applyMode,
    'trigger': trigger,
    'scope': scope,
    if (schedule != null) 'schedule': schedule,
    'timezone': timezone,
    'enabled': enabled,
  };
}
