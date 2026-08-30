/// A scope, a trigger, and an ordered series of steps.
///
/// Saved AI actions are a different thing — see
/// `areas/production_agent/ai_action.dart`. They meet only here: one kind of
/// step runs one of them.
class AutomationKinds {
  static const standard = 'standard';
  static const sectionWindow = 'section_window';
}

class Automation {
  const Automation({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.nameHe = '',
    this.trigger = const {},
    this.scope = const {},
    this.steps = const [],
    this.schedule,
    this.timezone = 'UTC',
    this.enabled = true,
    this.lastRunAt,
    this.nextRunAt,
    this.kind = AutomationKinds.standard,
    this.viewId,
    this.sectionKey,
    this.windowDurationMinutes,
    this.windowOpenedAt,
    this.windowClosesAt,
    this.pendingClear,
    this.pendingUserInput,
    this.windowOpen = false,
    this.attention = false,
    this.hasPendingReview = false,
  });

  final int id;
  final int workspaceId;
  final String name;
  final String nameHe;

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
  final String kind;
  final int? viewId;
  final String? sectionKey;
  final int? windowDurationMinutes;
  final DateTime? windowOpenedAt;
  final DateTime? windowClosesAt;
  final Map<String, dynamic>? pendingClear;
  final Map<String, dynamic>? pendingUserInput;
  final bool windowOpen;
  final bool attention;
  final bool hasPendingReview;

  bool get isScheduled => (schedule ?? '').isNotEmpty;
  bool get isSectionWindow => kind == AutomationKinds.sectionWindow;
  bool get isLockedToSection =>
      !isSectionWindow && viewId != null && (sectionKey ?? '').isNotEmpty;
  bool get hasPendingClear => pendingClear != null;

  factory Automation.fromJson(Map<String, dynamic> json) {
    final trigger = json['trigger'];
    final scope = json['scope'];
    final steps = json['steps'];
    return Automation(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      nameHe: json['name_he'] as String? ?? '',
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
      kind: json['kind'] as String? ?? AutomationKinds.standard,
      viewId: json['view_id'] as int?,
      sectionKey: json['section_key'] as String?,
      windowDurationMinutes: json['window_duration_minutes'] as int?,
      windowOpenedAt: DateTime.tryParse(json['window_opened_at'] as String? ?? ''),
      windowClosesAt: DateTime.tryParse(json['window_closes_at'] as String? ?? ''),
      pendingClear: json['pending_clear'] is Map
          ? Map<String, dynamic>.from(json['pending_clear'] as Map)
          : null,
      pendingUserInput: json['pending_user_input'] is Map
          ? Map<String, dynamic>.from(json['pending_user_input'] as Map)
          : null,
      windowOpen: json['window_open'] as bool? ?? false,
      attention: json['attention'] as bool? ?? false,
      hasPendingReview: json['has_pending_review'] as bool? ?? false,
    );
  }

  static bool stepRequiresUserInput(
    Map<String, dynamic> step, {
    bool Function(int actionId)? actionRequiresInput,
  }) {
    if (step['kind'] != StepKinds.ai) return false;
    if (step['requires_user_input'] == true) return true;
    final actionId = step['action_id'];
    if (actionId is int && actionRequiresInput != null) {
      return actionRequiresInput(actionId);
    }
    return false;
  }

  static bool stepNeedsReview(Map<String, dynamic> step) {
    if (step['kind'] != StepKinds.ai) return false;
    return (step['apply_mode'] as String? ?? '') == 'review';
  }

  static bool needsComplimentaryPlacement(
    List<Map<String, dynamic>> steps, {
    bool Function(int actionId)? actionRequiresInput,
    bool Function(int actionId)? actionNeedsReview,
  }) {
    for (final step in steps) {
      if (stepRequiresUserInput(step, actionRequiresInput: actionRequiresInput)) {
        return true;
      }
      if (stepNeedsReview(step)) return true;
      final actionId = step['action_id'];
      if (actionId is int && actionNeedsReview != null && actionNeedsReview(actionId)) {
        return true;
      }
    }
    return false;
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
  static const fillFile = 'fill_file';

  static const all = [ai, createFile, unmarkTasks, archiveFiles, fillFile];
}
