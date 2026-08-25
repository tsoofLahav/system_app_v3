import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web link on ⌘-click (Ctrl-click on non-Apple). Super Editor's
/// default launch handler only fires in interaction mode, which we do not use.
SuperEditorContentTapDelegateFactory cmdClickLinkTapHandlerFactory =
    (SuperEditorContext editContext) =>
        CmdClickLinkTapHandler(editContext.document);

class CmdClickLinkTapHandler extends ContentTapDelegate {
  CmdClickLinkTapHandler(this.document) {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  final Document document;

  bool _onKey(KeyEvent event) {
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _modifierHeld =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    if (!_modifierHeld) return null;
    return linkUriAt(document, hoverPosition) != null
        ? SystemMouseCursors.click
        : null;
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    if (!_modifierHeld) return TapHandlingInstruction.continueHandling;
    final tapPosition = details.documentLayout
        .getDocumentPositionNearestToOffset(details.layoutOffset);
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }
    final link = linkUriAt(document, tapPosition);
    if (link == null) return TapHandlingInstruction.continueHandling;
    unawaited(launchUrl(link, mode: LaunchMode.externalApplication));
    return TapHandlingInstruction.halt;
  }
}

Uri? linkUriAt(Document document, DocumentPosition position) {
  final nodePosition = position.nodePosition;
  if (nodePosition is! TextNodePosition) return null;
  final textNode = document.getNodeById(position.nodeId);
  if (textNode is! TextNode) return null;
  for (final attribution in textNode.text.getAllAttributionsAt(nodePosition.offset)) {
    if (attribution is LinkAttribution) return attribution.launchableUri;
  }
  return null;
}
