import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_language.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_segmented_toggle.dart';
import '../../ui/dialog_field_style.dart';
import '../topic_types/topic_type_dialog.dart';
import './shortcut_preferences_dialog.dart';

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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['ok']),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogChoiceField<AppLanguage>(
                label: s['language'],
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
              const SizedBox(height: DialogFieldStyle.fieldGap),
              AppDialogField(
                label: s['topicTypes'],
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () => showTopicTypesListDialog(
                      context: context,
                      state: state,
                    ),
                    child: Text(s['manageTopicTypes']),
                  ),
                ),
              ),
              const SizedBox(height: DialogFieldStyle.fieldGap),
              AppDialogField(
                label: s['reorderSidebar'],
                hint: s['reorderSidebarHint'],
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () {
                      final turningOn = !state.sidebarReorderMode;
                      state.toggleSidebarReorderMode();
                      if (turningOn && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(
                      state.sidebarReorderMode
                          ? s['doneReorderSidebar']
                          : s['startReorderSidebar'],
                    ),
                  ),
                ),
              ),
              if (!isPhoneLayout) ...[
                const SizedBox(height: DialogFieldStyle.fieldGap),
                AppDialogField(
                  label: s['shortcuts'],
                  hint: s['shortcutHint'],
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      onPressed: () => showShortcutPreferencesDialog(
                        context: context,
                        state: state,
                      ),
                      child: Text(s['shortcutManage']),
                    ),
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
