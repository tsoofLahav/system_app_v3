import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/shortcuts/shortcut_binding.dart';
import '../../core/shortcuts/shortcut_catalog.dart';
import '../../design_system/app_typography.dart';

class ShortcutPreferencesSection extends StatefulWidget {
  const ShortcutPreferencesSection({super.key, required this.state});

  final AppState state;

  @override
  State<ShortcutPreferencesSection> createState() =>
      _ShortcutPreferencesSectionState();
}

class _ShortcutPreferencesSectionState extends State<ShortcutPreferencesSection> {
  String? _capturingActionId;
  String? _captureError;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s['shortcuts'], style: AppTypography.metaStyle),
        const SizedBox(height: 4),
        Text(s['shortcutHint'], style: AppTypography.noteBodyStyle),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: ListView(
            children: [
              for (final category in ShortcutCategory.values)
                _CategoryGroup(
                  state: state,
                  category: category,
                  capturingActionId: _capturingActionId,
                  captureError: _captureError,
                  onStartCapture: _startCapture,
                  onCancelCapture: _cancelCapture,
                  onBindingCaptured: _handleBindingCaptured,
                ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => state.resetAllShortcuts(),
            child: Text(s['shortcutResetAll']),
          ),
        ),
      ],
    );
  }

  void _startCapture(String actionId) {
    setState(() {
      _capturingActionId = actionId;
      _captureError = null;
    });
  }

  void _cancelCapture() {
    setState(() {
      _capturingActionId = null;
      _captureError = null;
    });
  }

  Future<void> _handleBindingCaptured(
    String actionId,
    ShortcutBinding binding,
  ) async {
    final owner = state.shortcutBindings.bindingOwner(actionId, binding);
    if (owner != null) {
      final ownerAction = shortcutActionById(owner);
      final ownerLabel = ownerAction == null
          ? owner
          : state.strings[ownerAction.labelKey];
      setState(() {
        _captureError = state.strings.shortcutConflict(ownerLabel);
      });
      return;
    }
    await state.setShortcutBinding(actionId, binding);
    if (!mounted) return;
    _cancelCapture();
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.state,
    required this.category,
    required this.capturingActionId,
    required this.captureError,
    required this.onStartCapture,
    required this.onCancelCapture,
    required this.onBindingCaptured,
  });

  final AppState state;
  final ShortcutCategory category;
  final String? capturingActionId;
  final String? captureError;
  final ValueChanged<String> onStartCapture;
  final VoidCallback onCancelCapture;
  final Future<void> Function(String actionId, ShortcutBinding binding)
      onBindingCaptured;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final actions = kShortcutCatalog
        .where((action) => action.category == category)
        .toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            s[shortcutCategoryLabelKey(category)],
            style: AppTypography.metaStyle.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final action in actions)
          _ShortcutRow(
            state: state,
            action: action,
            capturing: capturingActionId == action.id,
            captureError: capturingActionId == action.id ? captureError : null,
            onStartCapture: () => onStartCapture(action.id),
            onCancelCapture: onCancelCapture,
            onBindingCaptured: (binding) =>
                onBindingCaptured(action.id, binding),
          ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.state,
    required this.action,
    required this.capturing,
    required this.captureError,
    required this.onStartCapture,
    required this.onCancelCapture,
    required this.onBindingCaptured,
  });

  final AppState state;
  final ShortcutAction action;
  final bool capturing;
  final String? captureError;
  final VoidCallback onStartCapture;
  final VoidCallback onCancelCapture;
  final ValueChanged<ShortcutBinding> onBindingCaptured;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final binding = state.shortcutBindings.bindingFor(action.id);
    final isDefault = !state.shortcutBindings.hasOverride(action.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(s[action.labelKey], style: AppTypography.noteBodyStyle),
          ),
          Expanded(
            flex: 2,
            child: capturing
                ? _CaptureChip(
                    strings: s,
                    error: captureError,
                    onCancel: onCancelCapture,
                    onCaptured: onBindingCaptured,
                  )
                : Chip(
                    label: Text(
                      binding.displayLabel(),
                      style: AppTypography.metaStyle,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
          TextButton(
            onPressed: capturing ? null : onStartCapture,
            child: Text(s['shortcutChange']),
          ),
          TextButton(
            onPressed: isDefault ? null : () => state.resetShortcut(action.id),
            child: Text(s['shortcutReset']),
          ),
        ],
      ),
    );
  }
}

class _CaptureChip extends StatefulWidget {
  const _CaptureChip({
    required this.strings,
    required this.error,
    required this.onCancel,
    required this.onCaptured,
  });

  final AppStrings strings;
  final String? error;
  final VoidCallback onCancel;
  final ValueChanged<ShortcutBinding> onCaptured;

  @override
  State<_CaptureChip> createState() => _CaptureChipState();
}

class _CaptureChipState extends State<_CaptureChip> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        final binding = shortcutBindingFromEvent(event);
        if (binding == null || !binding.isValid) {
          return KeyEventResult.ignored;
        }
        widget.onCaptured(binding);
        return KeyEventResult.handled;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            label: Text(
              s['shortcutPressKeys'],
              style: AppTypography.metaStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            visualDensity: VisualDensity.compact,
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.error!,
                style: AppTypography.metaStyle.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
