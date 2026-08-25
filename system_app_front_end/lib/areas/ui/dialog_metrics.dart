import 'package:flutter/material.dart';

/// Shared dialog sizing — panels hug their content (see UI AREA.md).
abstract final class AppDialogMetrics {
  /// Default max width for ordinary create/edit dialogs.
  static const maxWidth = 280.0;

  /// Wider panels only when the body needs it (tables, shortcut lists).
  static const wideWidth = 400.0;

  /// Calendar + compact clock side by side in the automation builder.
  static const extraWideWidth = 460.0;

  /// Real file editor hosted inside the fill-file automation step.
  static const fileEditorWidth = 520.0;

  static const compactCalendarDay = 20.0;

  /// Shared card size so the day and time pickers sit as a matching pair.
  static const compactPickerCardHeight = 252.0;

  static const padding = EdgeInsets.fromLTRB(12, 10, 12, 8);
  static const phoneInset = EdgeInsets.symmetric(horizontal: 14, vertical: 16);
  static const phoneTitlePadding = EdgeInsets.fromLTRB(12, 10, 12, 4);
  static const phoneBodyPadding = EdgeInsets.fromLTRB(12, 0, 12, 6);
  static const phoneActionsPadding = EdgeInsets.fromLTRB(6, 4, 6, 8);
  static const windowInset = EdgeInsets.symmetric(horizontal: 20, vertical: 20);

  static const titleGap = 4.0;
  static const bodyGap = 4.0;
  static const actionsGap = 6.0;
}
