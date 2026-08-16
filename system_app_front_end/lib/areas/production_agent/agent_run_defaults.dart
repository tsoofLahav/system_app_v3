/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// Consult always sends `apply_mode` from the dialog toggle (default review).
/// When omitted, the backend uses `DEFAULT_MANUAL_APPLY_MODE`. Automation
/// create needs this local default for the segmented control.
const defaultAutomationApplyMode = 'review';
