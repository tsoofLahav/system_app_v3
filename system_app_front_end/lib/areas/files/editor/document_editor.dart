import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../data/app_file.dart';
import './block_document_editor.dart';

class DocumentEditor extends StatelessWidget {
  const DocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
    this.minViewportHeight,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  /// Pane viewport height so empty space under the text stays tappable.
  final double? minViewportHeight;

  @override
  Widget build(BuildContext context) {
    // Do NOT wrap this in ListenableBuilder(listenable: state). Rebuilding the
    // document editor mid-keystroke desyncs Flutter's HardwareKeyboard and
    // throws "KeyDownEvent … physical key is already pressed" in a loop.
    // BlockDocumentEditor listens for embed changes itself, carefully.
    return BlockDocumentEditor(
      key: ValueKey('doc-${file.id}'),
      file: file,
      state: state,
      embeds: state.embedsByFileId[file.id] ?? embeds,
      minViewportHeight: minViewportHeight,
    );
  }
}
