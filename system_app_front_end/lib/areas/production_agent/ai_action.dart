import './agent_run_defaults.dart';

/// A prompt on a button.
///
/// Not an automation: nothing schedules it. It runs when the user presses it,
/// on whatever they have open. Scope only decides whether it sits on the bar;
/// every saved action is in the ⋯ menu.
class AiAction {
  const AiAction({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.prompt,
    required this.applyMode,
    this.nameHe = '',
    this.icon = '',
    this.barSlot,
    this.topicTypeId,
    this.topicId,
    this.requiresUserInput = false,
    this.userInputPrompt = '',
  });

  final int id;
  final int workspaceId;
  final String name;
  final String nameHe;
  final String prompt;
  final String applyMode;

  /// Key into the action icon vocabulary ([`action_icons.dart`]), not a code
  /// point — the set is ours to change without touching stored rows.
  final String icon;

  /// 1..7 for a fixed AI-bar seat, 9..10 for a topic extra, null for the menu.
  final int? barSlot;

  /// Null with [topicId] also null = every topic. Set = this type.
  final int? topicTypeId;

  /// Set = this topic only. Mutually exclusive with [topicTypeId].
  final int? topicId;

  final bool requiresUserInput;
  final String userInputPrompt;

  bool get isOnBar => barSlot != null;

  bool get isGlobal => topicId == null && topicTypeId == null;

  bool visibleOnTopicType(int? typeId) =>
      isGlobal || topicTypeId == typeId;

  bool visibleIn({
    required int? openTopicId,
    required int? openTypeId,
    required Set<int> visitingTopicIds,
    required Set<int> visitingTypeIds,
  }) {
    if (isGlobal) return true;
    if (topicId != null) {
      return topicId == openTopicId || visitingTopicIds.contains(topicId);
    }
    return topicTypeId == openTypeId || visitingTypeIds.contains(topicTypeId);
  }

  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
    id: json['id'] as int,
    workspaceId: json['workspace_id'] as int,
    name: json['name'] as String,
    nameHe: json['name_he'] as String? ?? '',
    prompt: json['prompt'] as String? ?? '',
    applyMode: json['apply_mode'] as String? ?? defaultConsultApplyMode,
    icon: json['icon'] as String? ?? '',
    barSlot: json['bar_slot'] as int?,
    topicTypeId: json['topic_type_id'] as int?,
    topicId: json['topic_id'] as int?,
    requiresUserInput: json['requires_user_input'] as bool? ?? false,
    userInputPrompt: json['user_input_prompt'] as String? ?? '',
  );
}
