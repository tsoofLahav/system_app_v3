import './agent_run_defaults.dart';

/// A prompt on a button.
///
/// Not an automation: nothing schedules it and it has no stored scope. It runs
/// when the user presses it, on whatever they have open — which is why they
/// pressed it there.
class AiAction {
  const AiAction({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.prompt,
    required this.applyMode,
    this.icon = '',
    this.barSlot,
    this.topicTypeId,
  });

  final int id;
  final int workspaceId;
  final String name;
  final String prompt;
  final String applyMode;

  /// Key into the action icon vocabulary ([`action_icons.dart`]), not a code
  /// point — the set is ours to change without touching stored rows.
  final String icon;

  /// 1..6 for an action on the AI bar, null for one that lives in the menu.
  final int? barSlot;

  /// Null = offered on every topic. Set = this type plus the globals.
  final int? topicTypeId;

  bool get isOnBar => barSlot != null;

  bool visibleOnTopicType(int? typeId) =>
      topicTypeId == null || topicTypeId == typeId;

  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
    id: json['id'] as int,
    workspaceId: json['workspace_id'] as int,
    name: json['name'] as String,
    prompt: json['prompt'] as String? ?? '',
    applyMode: json['apply_mode'] as String? ?? defaultConsultApplyMode,
    icon: json['icon'] as String? ?? '',
    barSlot: json['bar_slot'] as int?,
    topicTypeId: json['topic_type_id'] as int?,
  );
}
