import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../ux/dialogs/dialog_choice_list.dart';
import './ai_action_bar.dart';

enum AiActionScopeKind { all, type, topic }

class AiActionScopeChoice {
  const AiActionScopeChoice({
    required this.kind,
    this.typeId,
    this.topicId,
    this.label,
    this.labelKey,
  });

  final AiActionScopeKind kind;
  final int? typeId;
  final int? topicId;
  final String? label;
  final String? labelKey;

  bool matches(AiActionScopeKind kind, int? topicId, int? typeId) {
    if (this.kind != kind) return false;
    if (kind == AiActionScopeKind.topic) return this.topicId == topicId;
    if (kind == AiActionScopeKind.type) return this.typeId == typeId;
    return true;
  }

  String title(AppStrings strings) =>
      label ?? (labelKey != null ? strings[labelKey!] : '');
}

String aiActionScopeLabel(
  AppState state, {
  required AiActionScopeKind kind,
  int? topicId,
  int? typeId,
}) {
  final s = state.strings;
  switch (kind) {
    case AiActionScopeKind.all:
      return s['actionAppliesEveryTopic'];
    case AiActionScopeKind.type:
      final type = state.topicTypeById(typeId);
      return type == null
          ? s['scopeTopicType']
          : state.topicTypeDisplayName(type);
    case AiActionScopeKind.topic:
      final topic = state.allTopics.where((t) => t.id == topicId).firstOrNull;
      if (topic == null) return s['actionAppliesThisTopic'];
      return state.topicDisplayName(topic);
  }
}

/// Default create scope: the open topic when it still has an extra seat,
/// otherwise every topic.
({AiActionScopeKind kind, int? topicId, int? typeId}) defaultAiActionScope(
  AppState state, {
  int? initialTopicTypeId,
}) {
  if (initialTopicTypeId != null) {
    return (
      kind: AiActionScopeKind.type,
      topicId: null,
      typeId: initialTopicTypeId,
    );
  }
  final topicId = state.selectedTopic?.id;
  if (topicId == null || state.topicAiActionsFull(topicId)) {
    return (kind: AiActionScopeKind.all, topicId: null, typeId: null);
  }
  return (kind: AiActionScopeKind.topic, topicId: topicId, typeId: null);
}

Future<AiActionScopeChoice?> pickAiActionScope({
  required BuildContext context,
  required AppState state,
  required AiActionScopeKind kind,
  int? topicId,
  int? typeId,
  int? excludeActionId,
}) {
  final s = state.strings;
  final rows = <AiActionScopeChoice>[
    const AiActionScopeChoice(
      kind: AiActionScopeKind.all,
      labelKey: 'actionAppliesEveryTopic',
    ),
    for (final type in state.topicTypes)
      AiActionScopeChoice(
        kind: AiActionScopeKind.type,
        typeId: type.id,
        label: state.topicTypeDisplayName(type),
      ),
    for (final topic in state.activeTopics)
      if (topic.id == topicId ||
          !topicAiActionSlotsFull(
            state.aiActions,
            topic.id,
            excludeId: excludeActionId,
          ))
        AiActionScopeChoice(
          kind: AiActionScopeKind.topic,
          topicId: topic.id,
          label: state.topicDisplayName(topic),
        ),
  ];
  var initial = 0;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].matches(kind, topicId, typeId)) {
      initial = i;
      break;
    }
  }
  return showAppChoiceDialog<AiActionScopeChoice>(
    context: context,
    title: s['actionAppliesTo'],
    cancelLabel: s['cancel'],
    items: rows,
    initialIndex: initial,
    itemBuilder: (context, row, _) => DialogChoiceText(row.title(s)),
  );
}
