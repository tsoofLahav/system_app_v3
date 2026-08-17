import 'package:flutter/material.dart';

import './action_icons.dart';
import './adaptive_dialog.dart';
import './app_colors.dart';
import './app_icons.dart';
import './dialog_field_style.dart';
import './dialog_metrics.dart';

/// Pick the face a saved AI action wears on the bar.
///
/// A second dialog rather than a grid inside the form, the way colours and
/// emoji are picked ([AppDialogPickerField]) — the create form stays short.
Future<String?> showActionIconPicker({
  required BuildContext context,
  required String title,
  String? selectedKey,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(title),
      width: AppDialogMetrics.maxWidth,
      child: _ActionIconGrid(selectedKey: selectedKey),
    ),
  );
}

/// The current icon, opening the picker when tapped.
class ActionIconField extends StatelessWidget {
  const ActionIconField({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.pickerTitle,
    required this.iconKey,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final String pickerTitle;
  final String iconKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppDialogPickerField(
      label: label,
      preview: AppIcon(actionIcon(iconKey), size: 18),
      valueLabel: valueLabel,
      onTap: () async {
        final picked = await showActionIconPicker(
          context: context,
          title: pickerTitle,
          selectedKey: iconKey,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _ActionIconGrid extends StatelessWidget {
  const _ActionIconGrid({this.selectedKey});

  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final key in actionIconKeys)
          _IconChoice(
            iconKey: key,
            selected: key == selectedKey,
            onTap: () => Navigator.pop(context, key),
          ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBright.withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.noteBorder.withValues(alpha: 0.42),
              width: 0.8,
            ),
          ),
          child: Center(
            child: AppIcon(
              actionIcon(iconKey),
              size: 20,
              color: selected
                  ? Colors.white.withValues(alpha: 0.96)
                  : AppColors.text.withValues(alpha: 0.82),
            ),
          ),
        ),
      ),
    );
  }
}
