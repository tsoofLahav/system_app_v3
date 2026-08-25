import 'package:flutter/material.dart';

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
