import 'package:flutter/material.dart';
import 'dart:async';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../data/app_file.dart';
import '../data/topic.dart';
import '../../production_agent/pending_review_ui.dart';
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
    this.isBrought = false,
    this.autoOpenPendingReview = true,
    this.framed = true,
    this.showFileMenu = true,
  });

  final Topic topic;
  final AppFile file;
  final AppState state;
  final Color? accent;
  final VoidCallback onDelete;

  /// Visiting Home from another topic — dismiss from the file menu.
  final bool isBrought;

  /// Phone carousel mounts neighbors without opening their pending dialog.
  final bool autoOpenPendingReview;

  /// File card frame. Phone and desktop use the same framed look.
  final bool framed;

  /// Hide archive/delete when this pane is a throwaway snippet editor.
  final bool showFileMenu;

  @override
  State<DocumentPane> createState() => _DocumentPaneState();
}

class _DocumentPaneState extends State<DocumentPane> {
  late TextEditingController _titleController;
  final _titleFocus = FocusNode();
  final _menuButtonKey = GlobalKey();

  String get _shownName => widget.state.fileDisplayName(widget.file.name);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _shownName);
    _titleFocus.addListener(_onTitleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenPendingReview());
    });
  }

  @override
  void didUpdateWidget(DocumentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _titleController.text = _shownName;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOpenPendingReview());
      });
      return;
    }
    if (!oldWidget.autoOpenPendingReview && widget.autoOpenPendingReview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOpenPendingReview());
      });
    }
    // A rename from elsewhere (agent, another device) belongs on screen, but
    // never on top of what the user is in the middle of typing.
    if (!_titleFocus.hasFocus && _titleController.text != _shownName) {
      _titleController.text = _shownName;
    }
  }

  void _onTitleFocusChanged() {
    // Phone presentation: the title text is hidden most of the time, so we
    // need a rebuild on focus gain/loss to show it only when renaming.
    if (isPhoneLayout) setState(() {});
    if (!_titleFocus.hasFocus) unawaited(_saveTitle());
  }

  Future<void> _maybeOpenPendingReview() async {
    if (!mounted || !widget.autoOpenPendingReview) return;
    await openPendingReviewForFile(context, widget.state, widget.file.id);
  }

  @override
  void deactivate() {
    unawaited(DocumentEditorRegistry.flushActive());
    unawaited(_saveTitle());
    super.deactivate();
  }

  @override
  void dispose() {
    _titleFocus.removeListener(_onTitleFocusChanged);
    _titleFocus.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// Compared against the name as shown, not as stored: built-in files are
  /// displayed translated, so `Daily` reads `יומי` and an untouched header
  /// would otherwise rename the file to its own translation.
  Future<void> _saveTitle() async {
    final name = _titleController.text.trim();
    if (name.isEmpty || name == _shownName) return;
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
        if (widget.isBrought)
          AppContextMenuItem(value: 'dismiss', label: s['bringFileDismiss']),
        if (widget.isBrought) const AppContextMenuDivider(),
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
    if (value == 'dismiss') {
      await widget.state.dismissBroughtFile(widget.file.id);
      return;
    }
    if (value == 'archive') await _archive();
    if (value == 'delete') widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.state.fileById(widget.file.id) ?? widget.file;
    final hidePhoneTitleText = isPhoneLayout && !_titleFocus.hasFocus;
    final phoneTitleDecoration = hidePhoneTitleText
        ? const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          )
        : AppTypography.noteInputDecoration();

    final body = Padding(
      padding: AppSpacing.notePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPhoneLayout && widget.isBrought) ...[
            Text(
              widget.state.broughtFileOriginLabel(widget.topic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.metaStyle,
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  style: AppTypography.noteTitleStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: hidePhoneTitleText
                        ? Colors.transparent
                        : AppColors.text,
                  ),
                  decoration: phoneTitleDecoration,
                  cursorColor: AppColors.text,
                  // Clicking into the document is how a rename usually ends,
                  // so leaving the field has to save it, not only Enter.
                  onSubmitted: (_) => _titleFocus.unfocus(),
                ),
              ),
              if (widget.showFileMenu)
                _FileMenuButton(
                  buttonKey: _menuButtonKey,
                  tooltip: widget.state.strings['fileMenu'],
                  onPressed: _showFileMenu,
                ),
            ],
          ),
          if (!isPhoneLayout) const SizedBox(height: AppSpacing.xs),
          // Pane height is fixed by the topic layout (or the phone page).
          // Super Editor owns scrolling inside this slot.
          Expanded(
            child: DocumentEditor(file: file, state: widget.state),
          ),
        ],
      ),
    );

    if (!widget.framed) {
      if (widget.isBrought && widget.accent != null) {
        return ColoredBox(
          color: AppColors.uiAccent(widget.accent!).withValues(alpha: 0.06),
          child: body,
        );
      }
      return body;
    }

    return NoteCard(
      topicAccent: widget.accent,
      fileId: file.id,
      isMainTopic: widget.topic.isMain,
      child: body,
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
