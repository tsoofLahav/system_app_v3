import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/object_embed.dart';
import 'block_document_editor.dart';

class DocumentEditor extends StatelessWidget {
  const DocumentEditor({
    super.key,
    required this.file,
    required this.state,
    required this.embeds,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  Widget build(BuildContext context) {
    return BlockDocumentEditor(
      file: file,
      state: state,
      embeds: embeds,
    );
  }
}
