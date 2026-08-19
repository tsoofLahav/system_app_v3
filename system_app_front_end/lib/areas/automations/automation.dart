/// A scope, a trigger, and an ordered series of steps.
///
/// Saved AI actions are a different thing — see
/// `areas/production_agent/ai_action.dart`. They meet only here: one kind of
/// step runs one of them.
class Automation {
  const Automation({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.trigger = const {},
    this.scope = const {},
    this.steps = const [],
    this.schedule,
    this.timezone = 'UTC',
    this.enabled = true,
    this.lastRunAt,
    this.nextRunAt,
  });

  final int id;
  final int workspaceId;
  final String name;

  /// `{"type": "schedule"}` today; event types arrive with phase two.
  final Map<String, dynamic> trigger;

  /// `{"kind": "all" | "topic" | "topic_type", …}` — see `AutomationScope`.
  final Map<String, dynamic> scope;

  /// Each entry is `{"kind": …}` plus that kind's parameters.
  final List<Map<String, dynamic>> steps;

  final String? schedule;
  final String timezone;
  final bool enabled;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  bool get isScheduled => (schedule ?? '').isNotEmpty;

  factory Automation.fromJson(Map<String, dynamic> json) {
    final trigger = json['trigger'];
    final scope = json['scope'];
    final steps = json['steps'];
    return Automation(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      trigger: trigger is Map ? Map<String, dynamic>.from(trigger) : const {},
      scope: scope is Map ? Map<String, dynamic>.from(scope) : const {},
      steps: steps is List
          ? steps
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [],
      schedule: json['schedule'] as String?,
      timezone: json['timezone'] as String? ?? 'UTC',
      enabled: json['enabled'] as bool? ?? true,
      lastRunAt: DateTime.tryParse(json['last_run_at'] as String? ?? ''),
      nextRunAt: DateTime.tryParse(json['next_run_at'] as String? ?? ''),
    );
  }
}

/// The three shapes a scope can take, and the labels that read like a sentence.
class AutomationScope {
  static const all = 'all';
  static const topic = 'topic';
  static const topicType = 'topic_type';

  static String kindOf(Map<String, dynamic> scope) =>
      scope['kind'] as String? ?? all;

  static Map<String, dynamic> everywhere() => {'kind': all};
  static Map<String, dynamic> oneTopic(int topicId) => {
    'kind': topic,
    'topic_id': topicId,
  };
  static Map<String, dynamic> ofType(int typeId) => {
    'kind': topicType,
    'topic_type_id': typeId,
  };

  static int? typeIdOf(Map<String, dynamic> scope) {
    final raw = scope['topic_type_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  /// The topic a placeless step lands in, when the scope names exactly one.
  static int? targetTopicId(Map<String, dynamic> scope) =>
      kindOf(scope) == topic ? scope['topic_id'] as int? : null;
}

/// Step kinds, twinned with `STEP_SPECS` in
/// `areas/automations/services/steps.py`.
class StepKinds {
  static const ai = 'ai';
  static const createFile = 'create_file';
  static const unmarkTasks = 'unmark_tasks';
  static const archiveFiles = 'archive_files';

  static const all = [ai, createFile, unmarkTasks, archiveFiles];
}
