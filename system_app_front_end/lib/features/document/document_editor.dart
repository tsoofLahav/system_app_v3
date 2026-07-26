import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/object_embed.dart';
import '../../core/models/task.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';
import '../../shared/widgets/task_row.dart';
import '../document/document_body_parser.dart';

class DocumentEditor extends StatefulWidget {
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
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  late TextEditingController _bodyController;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.file.body);
  }

  @override
  void didUpdateWidget(DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        (!_dirty && oldWidget.file.body != widget.file.body)) {
      _bodyController.text = widget.file.body;
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _saveBody() async {
    if (!_dirty) return;
    await widget.state.updateFile(widget.file, {'body': _bodyController.text});
    _dirty = false;
  }

  ObjectEmbed? _embedForMarker(String marker) {
    for (final embed in widget.embeds) {
      final anchorMarker = embed.anchor['marker'] as String?;
      if (anchorMarker == marker) return embed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final segments = DocumentBodyParser.parse(_bodyController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final segment in segments)
          if (segment.isText)
            TextField(
              controller: TextEditingController(text: segment.text),
              maxLines: null,
              style: AppTypography.noteBodyStyle,
              decoration: AppTypography.noteInputDecoration(hint: ''),
              onChanged: (value) {
                final lines = _bodyController.text.split('\n');
                if (segment.lineIndex < lines.length) {
                  lines[segment.lineIndex] = value;
                  _bodyController.text = lines.join('\n');
                  _dirty = true;
                }
              },
              onEditingComplete: _saveBody,
            )
          else if (segment.marker != null)
            _EmbedSlot(
              marker: segment.marker!,
              embed: _embedForMarker(segment.marker!),
              state: widget.state,
              file: widget.file,
            ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () async {
              await widget.state.createTaskInDocument(widget.file);
            },
            icon: const Icon(Icons.add_task_outlined, size: 18),
            label: Text(widget.state.strings['addTask'] ?? 'Add task'),
          ),
        ),
      ],
    );
  }
}

class _EmbedSlot extends StatelessWidget {
  const _EmbedSlot({
    required this.marker,
    required this.embed,
    required this.state,
    required this.file,
  });

  final String marker;
  final ObjectEmbed? embed;
  final AppState state;
  final AppFile file;

  @override
  Widget build(BuildContext context) {
    if (embed?.task != null) {
      final task = embed!.task!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TaskRow(
          task: task,
          state: state,
          onToggle: () => state.toggleTaskStatus(task),
          onTitleChanged: (title) => state.updateTaskTitle(task, title),
          onDelete: () => state.deleteTask(task, file),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(marker, style: AppTypography.metaStyle),
    );
  }
}
