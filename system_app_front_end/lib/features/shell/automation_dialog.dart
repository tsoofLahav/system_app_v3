import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/services/api_service.dart';
import '../../design_system/adaptive_dialog.dart';
import '../../design_system/glass_surface.dart';

Future<void> showAutomationDialog({
  required BuildContext context,
  required AppState state,
}) async {
  final api = ApiService();
  final automations = await api.get('/automations?workspace_id=${state.workspaceId}') as List;
  if (!context.mounted) return;

  await showAppDialog<void>(
    context: context,
    builder: (ctx) => AppGlassDialog(
      title: Text(state.strings['automations'] ?? 'Automations'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(state.strings['close'] ?? 'Close')),
      ],
      child: SizedBox(
        width: 420,
        child: automations.isEmpty
            ? Text(state.strings['noAutomations'] ?? 'No automations yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in automations)
                    ListTile(
                      title: Text(row['name']?.toString() ?? 'Automation'),
                      subtitle: Text(row['apply_mode']?.toString() ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () async {
                          await api.post('/automations/${row['id']}/run', {});
                        },
                      ),
                    ),
                ],
              ),
      ),
    ),
  );
}
