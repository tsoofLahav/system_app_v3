import 'package:flutter/material.dart';
import 'dart:async';

import '../../../core/app_state.dart';
import '../data/app_file.dart';
import '../data/topic.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/note_widgets.dart';
import '../../ux/widgets/app_context_menu.dart';
import './document_editor_controller.dart';
import './document_editor.dart';

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
  final _menuButtonKey = GlobalKey();

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
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['archiveFileTitle'],
      message: s.archiveFileMessage(
        widget.state.fileDisplayName(widget.file.name),
      ),
      confirmLabel: s['archive'],
      cancelLabel: s['cancel'],
    );
    if (ok) await widget.state.archiveFile(widget.file);
  }

  /// The file's own menu. It is the right-click menu in every way but how it
  /// is opened, so it uses the same bubble rather than a Material popup.
  Future<void> _showFileMenu() async {
    final s = widget.state.strings;
    final box = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final isRtl = s.isRtl;
    final corner = box.localToGlobal(
      Offset(isRtl ? 0 : box.size.width, box.size.height + 2),
    );

    final value = await AppContextMenu.show(
      context: context,
      globalPosition: corner,
      isRtl: isRtl,
      entries: [
        AppContextMenuItem(value: 'archive', label: s['archiveFile']),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'delete',
          label: s['delete'],
          destructive: true,
        ),
      ],
    );

    if (!mounted || value == null) return;
    if (value == 'archive') await _archive();
    if (value == 'delete') widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.state.selectedDetail?.files
            .where((f) => f.id == widget.file.id)
            .firstOrNull ??
        widget.file;

    return NoteCard(
      topicAccent: widget.accent,
      fileId: file.id,
      isMainTopic: widget.topic.isMain,
      child: Padding(
        padding: AppSpacing.notePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
                _FileMenuButton(
                  buttonKey: _menuButtonKey,
                  tooltip: widget.state.strings['fileMenu'],
                  onPressed: _showFileMenu,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // The pane is one slot of the topic's layout, so its height is
            // fixed and the document scrolls inside it rather than pushing the
            // pane taller.
            Flexible(
              child: SingleChildScrollView(
                child: DocumentEditor(file: file, state: widget.state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dots in the corner of a file.
///
/// Quiet at rest — a file's own name should be the only thing drawing the eye
/// on that row — and it wakes up on hover. Lucide at the app's stroke weight,
/// like every other icon.
class _FileMenuButton extends StatefulWidget {
  const _FileMenuButton({
    required this.buttonKey,
    required this.tooltip,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_FileMenuButton> createState() => _FileMenuButtonState();
}

class _FileMenuButtonState extends State<_FileMenuButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: widget.buttonKey,
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Center(
              child: AppIcon(
                AppIcons.more,
                size: 16,
                color: AppColors.text.withValues(alpha: _hovered ? 0.72 : 0.34),
              ),
            ),
          ),
        ),
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
