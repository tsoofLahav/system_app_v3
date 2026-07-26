import 'package:flutter/material.dart';

import 'block_text_focus.dart';
import 'span_text_editing_controller.dart';
import 'text_formatting.dart';

/// Pull block content into the controller only when the field is idle.
///
/// See [RICH_TEXT.md] — never sync while the user is editing.
void syncRichControllerFromBlockIfIdle({
  required FocusNode focusNode,
  required Map<String, dynamic> blockContent,
  required SpanTextEditingController controller,
}) {
  if (focusNode.hasFocus || BlockTextFocusRegistry.isInMenuSession) {
    return;
  }
  // After the context menu closes, focus is often still lost for a frame while
  // the field remains the active editor. Syncing here overwrote spans and
  // caused formatting to "drag" onto newly typed text.
  if (BlockTextFocusRegistry.activeController == controller) {
    return;
  }

  final rich = richContentFromBlock(blockContent);
  if (rich.text == controller.text && _spansEqual(rich.spans, controller.spans)) {
    return;
  }

  controller.setRichState(
    text: rich.text,
    spans: rich.spans,
    preserveSelection: false,
  );
}

bool _spansEqual(
  List<Map<String, dynamic>> a,
  List<Map<String, dynamic>> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left['start'] != right['start'] ||
        left['end'] != right['end'] ||
        left['bold'] != right['bold'] ||
        left['italic'] != right['italic'] ||
        left['underline'] != right['underline'] ||
        left['size'] != right['size']) {
      return false;
    }
  }
  return true;
}
