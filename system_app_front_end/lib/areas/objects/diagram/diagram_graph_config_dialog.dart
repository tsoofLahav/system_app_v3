import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_segmented_toggle.dart';
import '../../ui/dialog_field_style.dart';
import '../data/object_service.dart';

Future<void> showDiagramGraphConfigDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => DiagramGraphConfigDialog(state: state),
  );
}

class DiagramGraphConfigDialog extends StatelessWidget {
  const DiagramGraphConfigDialog({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.strings;
        return AppAdaptiveDialogShell(
          title: Text(s['diagramGraphConfig']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['ok']),
            ),
          ],
          child: AppDialogChoiceField<DiagramColorMode>(
            label: s['diagramGraphColors'],
            options: [
              AppSegmentedOption(
                value: DiagramColorMode.byTopic,
                label: s['diagramColorByTopic'],
              ),
              AppSegmentedOption(
                value: DiagramColorMode.byTag,
                label: s['diagramColorByTag'],
              ),
            ],
            selected: state.diagramColorMode,
            onSelected: state.setDiagramColorMode,
          ),
        );
      },
    );
  }
}
