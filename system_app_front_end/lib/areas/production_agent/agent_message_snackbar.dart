import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../files/editor/document_editor_controller.dart';

/// How long an agent summary / error stays up. Longer than a default
/// Material snackbar so a "I cannot …" reply is readable; X dismisses early.
const agentMessageSnackDuration = Duration(seconds: 10);

void showAgentMessageSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: agentMessageSnackDuration,
      showCloseIcon: true,
    ),
  );
}

void notifySelectedTextTruncation(
  BuildContext context,
  AppStrings strings,
  AgentMarkedText? mark,
) {
  if (mark == null || !mark.truncated) return;
  showAgentMessageSnackBar(
    context,
    strings.markedTextTruncated(
      DocumentEditorRegistry.agentSelectedTextMaxChars,
    ),
  );
}
