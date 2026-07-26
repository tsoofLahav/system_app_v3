import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';
import 'document_editor_controller.dart';
import 'document_editor.dart';

class DocumentPane extends StatefulWidget {
  const DocumentPane({
    super.key,
    required this.topic,
    required this.file,
    required this.state,
    this.accent,
    required this.onDelete,
  });

  final Topic topic;
  final AppFile file;
  final AppState state;
  final Color? accent;
  final VoidCallback onDelete;

  @override
  State<DocumentPane> createState() => _DocumentPaneState();
}

class _DocumentPaneState extends State<DocumentPane> {
  late TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.state.fileDisplayName(widget.file.name),
    );
  }

  @override
  void didUpdateWidget(DocumentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _titleController.text = widget.state.fileDisplayName(widget.file.name);
    }
  }

  @override
  void deactivate() {
    unawaited(DocumentEditorRegistry.flushActive());
    super.deactivate();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    final name = _titleController.text.trim();
    if (name.isEmpty || name == widget.file.name) return;
    await widget.state.updateFile(widget.file, {'name': name});
  }

  Future<void> _archive() async {
    final s = widget.state.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['archiveFileTitle'] ?? 'Archive file?'),
        content: Text(s['archiveFileMessage'] ?? 'Archive this file?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['archive'])),
        ],
      ),
    );
    if (ok == true) await widget.state.archiveFile(widget.file);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.state.selectedDetail?.files
            .where((f) => f.id == widget.file.id)
            .firstOrNull ??
        widget.file;

    return NoteCard(
      topicAccent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  style: AppTypography.noteTitleStyle,
                  decoration: AppTypography.noteInputDecoration(),
                  onSubmitted: (_) => _saveTitle(),
                  onEditingComplete: _saveTitle,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'archive') _archive();
                  if (value == 'delete') widget.onDelete();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(widget.state.strings['archiveFile'] ?? 'Archive'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(widget.state.strings['delete'] ?? 'Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          DocumentEditor(file: file, state: widget.state),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
