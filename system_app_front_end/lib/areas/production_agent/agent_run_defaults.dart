/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// A saved action opens on direct apply — the undo toast is the lighter path
/// for a prompt you press and watch. An automation step defaults to review,
/// because nobody is watching at 2am.
const defaultConsultApplyMode = 'direct_apply';
const defaultAutomationApplyMode = 'review';

/// Seats on the AI bar for saved actions, beside the agent button that is
/// always there. Twin of `AI_BAR_SLOTS` in
/// `areas/production_agent/services/action_bar.py`; slot n is also its
/// shortcut.
const aiBarSlotCount = 6;
