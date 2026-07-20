import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_language.dart';
import '../../core/platform/app_form_factor.dart';
import '../../design_system/adaptive_dialog.dart';
import '../../design_system/app_segmented_toggle.dart';
import '../../design_system/app_typography.dart';
import 'shortcut_preferences_dialog.dart';

Future<void> showPreferencesDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => PreferencesDialog(state: state),
  );
}

class PreferencesDialog extends StatelessWidget {
  const PreferencesDialog({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.strings;

        return AppAdaptiveDialogShell(
          title: Text(s['preferences']),
          width: 480,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['ok']),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s['language'], style: AppTypography.metaStyle),
              const SizedBox(height: 8),
              AppSegmentedToggle<AppLanguage>(
                options: [
                  AppSegmentedOption(
                    value: AppLanguage.en,
                    label: s['english'],
                  ),
                  AppSegmentedOption(
                    value: AppLanguage.he,
                    label: s['hebrew'],
                  ),
                ],
                selected: state.language,
                onSelected: state.setLanguage,
              ),
              if (!isPhoneLayout) ...[
                const SizedBox(height: 24),
                Text(s['shortcuts'], style: AppTypography.metaStyle),
                const SizedBox(height: 4),
                Text(s['shortcutHint'], style: AppTypography.noteBodyStyle),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () => showShortcutPreferencesDialog(
                      context: context,
                      state: state,
                    ),
                    child: Text(s['shortcutManage']),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
