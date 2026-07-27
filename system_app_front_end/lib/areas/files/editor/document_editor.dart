import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/app_file.dart';
import './block_document_editor.dart';

class DocumentEditor extends StatelessWidget {
  const DocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
  });

  final AppFile file;
  final AppState state;
  final List<dynamic> embeds;

  @override
  Widget build(BuildContext context) {
    return BlockDocumentEditor(
      file: file,
      state: state,
      embeds: embeds,
    );
  }
}
