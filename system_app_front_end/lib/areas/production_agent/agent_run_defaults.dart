/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// A saved action opens on direct apply — the undo toast is the lighter path
/// for a prompt you press and watch. An automation step defaults to review,
/// because nobody is watching at 2am.
const defaultConsultApplyMode = 'direct_apply';
const defaultAutomationApplyMode = 'review';

/// Fixed saved-action seats on the AI bar (global / type-scoped). Twin of
/// `AI_BAR_SLOTS` in `areas/production_agent/services/action_bar.py`.
/// The eight spots on the bar count the agent as ⌘1; these seven are ⌘2…⌘8.
const aiBarSlotCount = 7;

/// Extra seats a topic-scoped action occupies only on that topic (⌘9 / ⌘0).
const aiTopicExtraSlotCount = 2;
const aiTopicExtraFirstSlot = 9;
const aiTopicActionsPerTopic = 2;
