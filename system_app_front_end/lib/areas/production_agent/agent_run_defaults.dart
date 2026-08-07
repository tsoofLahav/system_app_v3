/// UI defaults that must stay aligned with backend `shared/run_config.py`.
///
/// Manual consult does **not** send `apply_mode` — the backend owns
/// `DEFAULT_MANUAL_APPLY_MODE`. Only automation create needs a local default
/// for the segmented control.
const defaultAutomationApplyMode = 'review';
