/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// Consult always sends `apply_mode` from the dialog toggle, which opens on
/// direct apply — the undo toast is the lighter path for a one-off ask.
/// When omitted, the backend uses `DEFAULT_MANUAL_APPLY_MODE`. Automation
/// create needs this local default for the segmented control.
const defaultAutomationApplyMode = 'review';

/// Seats on the AI bar for saved actions, beside the agent button that is
/// always there. Twin of `AI_BAR_SLOTS` in
/// `areas/automations/services/action_bar.py`; slot n is also its shortcut.
const aiBarSlotCount = 6;
