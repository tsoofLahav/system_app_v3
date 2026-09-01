import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import './block_text_actions.dart';
import './document_context_menu.dart';
import './formatted_text_field.dart';

/// A dialog multiline field that uses the same caret / mark rules as object
/// editors ([FormattedTextField]): click placement, RTL motion, grapheme-safe
/// marking, Shift+Enter newline.
class DialogFormattedField extends StatelessWidget {
  const DialogFormattedField({
    super.key,
    required this.controller,
    required this.strings,
    this.focusNode,
    this.minLines = 3,
    this.maxLines,
    this.hintText,
    this.onChanged,
    this.onEnter,
  });

  final TextEditingController controller;
  final AppStrings strings;
  final FocusNode? focusNode;
  final int minLines;
  final int? maxLines;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEnter;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: DialogFieldStyle.decoration(),
      child: FormattedTextField(
        controller: controller,
        focusNode: focusNode,
        style: AppTypography.noteBodyStyle,
        minLines: minLines,
        maxLines: maxLines,
        hintText: hintText,
        onChanged: onChanged,
        onEnter: onEnter,
        onSecondaryTapDown: (details) {
          unawaited(
            DocumentContextMenu.showTextMenu(
              context: context,
              globalPosition: details.globalPosition,
              strings: strings,
              onAction: runBlockTextAction,
            ),
          );
        },
      ),
    );
  }
}
