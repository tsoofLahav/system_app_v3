import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../data/app_file.dart';
import './super_document_editor.dart';

class DocumentEditor extends StatelessWidget {
  const DocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  Widget build(BuildContext context) {
    // Do NOT wrap this in ListenableBuilder(listenable: state). Rebuilding the
    // document editor mid-keystroke desyncs Flutter's HardwareKeyboard and
    // throws "KeyDownEvent … physical key is already pressed" in a loop.
    // SuperDocumentEditor listens for embed changes itself, carefully.
    return SuperDocumentEditor(
      key: ValueKey('doc-${file.id}'),
      file: file,
      state: state,
      embeds: state.embedsByFileId[file.id] ?? embeds,
    );
  }
}
