/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// A saved action opens on direct apply — the undo toast is the lighter path
/// for a prompt you press and watch. An automation step defaults to review,
/// because nobody is watching at 2am.
const defaultConsultApplyMode = 'direct_apply';
const defaultAutomationApplyMode = 'review';

/// Fixed saved-action seats on the AI bar (global / type-scoped). Twin of
/// `AI_BAR_SLOTS` in `areas/production_agent/services/action_bar.py`.
/// Preserve legacy seat IDs and shortcuts; five additional seats are unbound.
const aiFixedBarSlots = <int>[1, 2, 3, 4, 5, 6, 7, 11, 12, 13, 14, 15];
final aiBarSlotCount = aiFixedBarSlots.length;

/// Extra seats a topic-scoped action occupies only on that topic (⌘9 / ⌘0).
const aiTopicExtraSlotCount = 2;
const aiTopicExtraFirstSlot = 9;
const aiTopicActionsPerTopic = 2;
