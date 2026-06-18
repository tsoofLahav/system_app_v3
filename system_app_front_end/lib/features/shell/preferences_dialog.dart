import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_language.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<void> showPreferencesDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showDialog<void>(
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

        return AppGlassDialog(
          title: Text(s['preferences']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['ok']),
            ),
          ],
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['language'], style: AppTypography.metaStyle),
                const SizedBox(height: 8),
                SegmentedButton<AppLanguage>(
                  segments: [
                    ButtonSegment(
                      value: AppLanguage.en,
                      label: Text(s['english']),
                    ),
                    ButtonSegment(
                      value: AppLanguage.he,
                      label: Text(s['hebrew']),
                    ),
                  ],
                  selected: {state.language},
                  onSelectionChanged: (selection) {
                    state.setLanguage(selection.first);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
