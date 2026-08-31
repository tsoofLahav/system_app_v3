import './agent_run_defaults.dart';
import './ai_action.dart';

bool isFixedAiBarSlot(int slot) => slot >= 1 && slot <= aiBarSlotCount;

bool isTopicExtraAiBarSlot(int slot) {
  return slot >= aiTopicExtraFirstSlot &&
      slot < aiTopicExtraFirstSlot + aiTopicExtraSlotCount;
}

int topicAiActionCount(
  List<AiAction> actions,
  int topicId, {
  int? excludeId,
}) {
  var n = 0;
  for (final action in actions) {
    if (action.topicId != topicId) continue;
    if (excludeId != null && action.id == excludeId) continue;
    n++;
  }
  return n;
}

bool topicAiActionSlotsFull(
  List<AiAction> actions,
  int topicId, {
  int? excludeId,
}) {
  return topicAiActionCount(actions, topicId, excludeId: excludeId) >=
      aiTopicActionsPerTopic;
}

int? firstFreeFixedAiBarSlot(List<AiAction> actions) {
  final taken = {
    for (final action in actions)
      if (action.topicId == null &&
          action.barSlot != null &&
          isFixedAiBarSlot(action.barSlot!))
        action.barSlot!,
  };
  for (var slot = 1; slot <= aiBarSlotCount; slot++) {
    if (!taken.contains(slot)) return slot;
  }
  return null;
}

int? firstFreeTopicExtraSlot(List<AiAction> actions, int topicId) {
  final taken = {
    for (final action in actions)
      if (action.topicId == topicId &&
          action.barSlot != null &&
          isTopicExtraAiBarSlot(action.barSlot!))
        action.barSlot!,
  };
  for (var i = 0; i < aiTopicExtraSlotCount; i++) {
    final slot = aiTopicExtraFirstSlot + i;
    if (!taken.contains(slot)) return slot;
  }
  return null;
}

/// Fixed seats in slot order, then up to two extras (open topic first).
List<AiAction> composeBarAiActions({
  required List<AiAction> actions,
  required int? openTopicId,
  required int? openTypeId,
  required Set<int> visitingTopicIds,
  required Set<int> visitingTypeIds,
}) {
  bool shown(AiAction action) => action.visibleIn(
        openTopicId: openTopicId,
        openTypeId: openTypeId,
        visitingTopicIds: visitingTopicIds,
        visitingTypeIds: visitingTypeIds,
      );

  final fixed = [
    for (final action in actions)
      if (shown(action) &&
          action.topicId == null &&
          action.barSlot != null &&
          isFixedAiBarSlot(action.barSlot!))
        action,
  ]..sort((a, b) => a.barSlot!.compareTo(b.barSlot!));

  final extras = [
    for (final action in actions)
      if (shown(action) &&
          action.topicId != null &&
          action.barSlot != null &&
          isTopicExtraAiBarSlot(action.barSlot!))
        action,
  ]..sort((a, b) {
      final aOpen = a.topicId == openTopicId ? 0 : 1;
      final bOpen = b.topicId == openTopicId ? 0 : 1;
      if (aOpen != bOpen) return aOpen.compareTo(bOpen);
      return a.barSlot!.compareTo(b.barSlot!);
    });

  return [
    ...fixed,
    ...extras.take(aiTopicExtraSlotCount),
  ];
}
