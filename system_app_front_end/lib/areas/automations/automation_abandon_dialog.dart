import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/confirm_dialog.dart';

Future<bool> showAutomationAbandonChangesDialog({
  required BuildContext context,
  required AppState state,
}) {
  final s = state.strings;
  return showAppConfirmDialog(
    context: context,
    title: s['automationAbandonTitle'],
    message: s['automationAbandonBody'],
    confirmLabel: s['automationAbandonConfirm'],
    cancelLabel: s['cancel'],
    destructive: true,
  );
}
