import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';

class ArchiveFilePreview extends StatelessWidget {
  const ArchiveFilePreview({
    super.key,
    required this.state,
    required this.file,
  });

  final AppState state;
  final AppFile file;

  @override
  Widget build(BuildContext context) {
    return NoteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.fileDisplayName(file.name),
            style: AppTypography.noteTitleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            file.body.isEmpty ? '(empty)' : file.body,
            style: AppTypography.noteBodyStyle,
          ),
        ],
      ),
    );
  }
}
