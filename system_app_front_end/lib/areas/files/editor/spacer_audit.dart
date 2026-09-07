/// Temporary blank-line forensics helper. Not wired — see DOCUMENT_FLOW.md
/// § Spacer audit to re-enable call sites. Search console for `spacerAudit`.
library;

import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import '../model/document_text_codec.dart';

/// Log marker-text body shape. Prefix: `spacerAudit`.
void spacerAuditBody(String tag, String? raw, {int? fileId}) {
  if (!kDebugMode) return;
  final body = DocumentTextCodec.stripHeader(raw ?? '');
  final spacers = _spacerMarkerCount(body);
  final hash = body.hashCode.toRadixString(16);
  final id = fileId == null ? '' : ' file=$fileId';
  debugPrint(
    'spacerAudit $tag$id spacers=$spacers len=${body.length} hash=$hash',
  );
}

/// Log live Super Editor empty paragraphs vs serialized spacers.
void spacerAuditDocument(String tag, Document doc, {int? fileId}) {
  if (!kDebugMode) return;
  var empties = 0;
  for (var i = 0; i < doc.nodeCount; i++) {
    final node = doc.getNodeAt(i);
    if (node is ParagraphNode && node.text.toPlainText().trim().isEmpty) {
      empties++;
    }
  }
  final id = fileId == null ? '' : ' file=$fileId';
  debugPrint('spacerAudit $tag$id emptyParas=$empties nodes=${doc.nodeCount}');
}

int _spacerMarkerCount(String body) {
  if (body.isEmpty) return 0;
  return RegExp(
    r'\[SPACER(?:\s+n="\d+")?\s*\]',
    caseSensitive: false,
  ).allMatches(body).length;
}
