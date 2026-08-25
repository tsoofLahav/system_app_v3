import 'package:flutter/material.dart';

import './app_colors.dart';
import './app_icons.dart';
import './app_segmented_toggle.dart';
import './app_typography.dart';

abstract final class DialogFieldStyle {
  /// Gap between a field's name and the field itself.
  static const labelGap = 3.0;

  /// Gap between one field and the next.
  static const fieldGap = 8.0;

  static InputDecoration decoration({String? hintText}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: AppColors.noteBorder.withValues(alpha: 0.68),
        width: 0.85,
      ),
    );
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.54),
          width: 0.9,
        ),
      ),
      border: border,
    );
  }

  /// The name of a field, in small letters above it.
  static TextStyle get labelStyle =>
      AppTypography.metaStyle.copyWith(fontSize: 11, height: 1.2);

  /// Ring around a keyboard pane (emoji grid, colour presets, HSV area).
  /// Same weight and teal as a focused [AppDialogPickerField].
  static BoxDecoration paneFocusDecoration({required bool focused}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: focused
            ? AppColors.primary.withValues(alpha: 0.54)
            : Colors.transparent,
        width: 0.9,
      ),
    );
  }
}

/// One line under a picker that has more than one keyboard pane.
class DialogKeyboardHint extends StatelessWidget {
  const DialogKeyboardHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DialogFieldStyle.labelStyle.copyWith(color: AppColors.textHint),
    );
  }
}

/// One labelled thing in a dialog.
///
/// The name sits **above** the field rather than inside it as a placeholder,
/// so it is still readable once the user has typed. Every dialog states its
/// fields this way; a bare `TextField` in a dialog is a style bug.
class AppDialogField extends StatelessWidget {
  const AppDialogField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;

  /// A word of guidance under the field, when the label cannot say it all.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(label, style: DialogFieldStyle.labelStyle),
        ),
        const SizedBox(height: DialogFieldStyle.labelGap),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(hint!, style: DialogFieldStyle.labelStyle),
          ),
        ],
      ],
    );
  }
}

/// A labelled set of choices, one of them chosen.
///
/// The chosen one is filled in bright teal — the app's single way of saying
/// "this is the one", used here exactly as the preferences dialog uses it.
class AppDialogChoiceField<T> extends StatelessWidget {
  const AppDialogChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<AppSegmentedOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppDialogField(
      label: label,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppSegmentedToggle<T>(
          options: options,
          selected: selected,
          onSelected: onSelected,
          enabled: enabled,
        ),
      ),
    );
  }
}

/// A field whose value is picked somewhere else — a colour, an emoji.
///
/// It shows what is chosen now and opens a second dialog to change it, so a
/// dialog never grows a picker inside itself.
class AppDialogPickerField extends StatelessWidget {
  const AppDialogPickerField({
    super.key,
    required this.label,
    required this.preview,
    required this.valueLabel,
    required this.onTap,
  });

  final String label;

  /// The current value, drawn: a swatch, an emoji, a small icon.
  final Widget preview;

  /// The current value in words, for whoever cannot read the preview.
  final String valueLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppDialogField(
      label: label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: focused
                          ? AppColors.primary.withValues(alpha: 0.54)
                          : AppColors.noteBorder.withValues(alpha: 0.68),
                      width: focused ? 0.9 : 0.85,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      preview,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          valueLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.noteBodyStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.text.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      AppIcon(
                        Directionality.of(context) == TextDirection.rtl
                            ? AppIcons.chevronLeft
                            : AppIcons.chevronRight,
                        size: 16,
                        color: AppColors.text.withValues(alpha: 0.38),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
