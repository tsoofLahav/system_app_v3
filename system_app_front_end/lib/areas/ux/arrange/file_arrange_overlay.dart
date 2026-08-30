import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ui/overlay_dialog_shell.dart';
import '../../ui/overlay_dialog_style.dart';
import '../layout/topic_file_slots.dart';
import '../topic/topic_appearance.dart';
import './arrange_file_chip_grid.dart';
import './file_arrange_draft.dart';
import './file_arrange_keyboard.dart';

Future<bool?> showFileArrangeOverlay(BuildContext context, AppState state) {
  final topic = state.selectedDetail?.topic;
  if (topic == null) return Future.value(null);

  return showDialog<bool>(
    context: context,
    barrierColor: OverlayDialogStyle.deepBarrierColor,
    barrierDismissible: true,
    builder: (_) => FileArrangeOverlay(state: state, topic: topic),
  ).then((result) {
    DocumentEditorRegistry.restoreActiveWritingFocus();
    return result;
  });
}

class FileArrangeOverlay extends StatefulWidget {
  const FileArrangeOverlay({
    super.key,
    required this.state,
    required this.topic,
  });

  final AppState state;
  final Topic topic;

  @override
  State<FileArrangeOverlay> createState() => _FileArrangeOverlayState();
}

class _FileArrangeOverlayState extends State<FileArrangeOverlay> {
  static const _bottomBarHeight = 42.0;

  final _focusNode = FocusNode(debugLabel: 'fileArrangeOverlay');
  late FileArrangeDraft _draft;
  ArrangeBottomFocus _bottomFocus = const ArrangeBottomFocus.done();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final detail = widget.state.selectedDetail!;
    final ordered = widget.state.orderedFilesFor(widget.topic, detail.files);
    _draft = FileArrangeDraft(
      ordered: ordered,
      layoutId: effectiveLayoutId(
        widget.state.layoutFor(widget.topic),
        ordered.length,
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _overlayWidth {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth - 40).clamp(640.0, 900.0);
  }

  Topic _topicFor(AppFile file) =>
      widget.state.canvasTopicFor(widget.topic, file);

  Color _accentFor(AppFile file) => TopicAppearance.accentFor(_topicFor(file));

  void _onMove(int from, int to) {
    if (_saving) return;
    if (!_draft.move(from, to)) return;
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final error = await widget.state.reorderTopicFiles(
      widget.topic,
      ordered: _draft.ordered,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _bottomFocus = _bottomFocus.step(
          layoutCount: 0,
          delta: spatialHorizontalDelta(
            isRtl: widget.state.isRtl,
            isLeftArrow: true,
          ),
        );
        setState(() {});
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _bottomFocus = _bottomFocus.step(
          layoutCount: 0,
          delta: spatialHorizontalDelta(
            isRtl: widget.state.isRtl,
            isLeftArrow: false,
          ),
        );
        setState(() {});
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        if (_bottomFocus.target == ArrangeBottomFocusTarget.cancel) {
          if (!_saving) Navigator.of(context).pop(false);
        } else {
          _save();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (!_saving) Navigator.of(context).pop(false);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final maxBodyHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: OverlayDialogShell(
        onDismiss: _saving ? null : () => Navigator.of(context).pop(false),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: _overlayWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              Text(
                s['arrangeFiles'],
                style: AppTypography.metaStyle.copyWith(
                  color: AppColors.text.withValues(alpha: 0.78),
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBodyHeight),
                child: _draft.ordered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          s['noFilesYet'],
                          style: AppTypography.noteBodyStyle.copyWith(
                            color: AppColors.noteHint,
                          ),
                        ),
                      )
                    : CustomScrollView(
                        shrinkWrap: true,
                        slivers: [
                          SliverToBoxAdapter(
                            child: ArrangeFileChipGrid(
                              files: _draft.ordered,
                              shownCount: _draft.shownCount,
                              onScreenLabel: s['arrangeOnScreen'],
                              offScreenLabel: s['arrangeOffScreen'],
                              displayNameFor: (file) =>
                                  widget.state.fileDisplayName(file.name),
                              topicFor: _topicFor,
                              accentFor: _accentFor,
                              loadAgentText: widget.state.loadPreviewAgentText,
                              strings: s,
                              onMove: _onMove,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _buildBottomBars(s),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBars(AppStrings s) {
    return GlassBarSegment(
      height: _bottomBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChromeIconButton(
            tooltip: s['cancel'],
            icon: AppIcons.close,
            focused: _bottomFocus.target == ArrangeBottomFocusTarget.cancel,
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          ),
          _ChromeIconButton(
            tooltip: s['arrangeDone'],
            icon: AppIcons.check,
            focused: _bottomFocus.target == ArrangeBottomFocusTarget.done,
            onPressed: _saving ? null : _save,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.focused = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: focused
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: primary.withValues(alpha: 0.9),
                  width: 1.5,
                ),
              )
            : const BoxDecoration(),
        child: IconButton(
          onPressed: onPressed,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: Icon(
            icon,
            size: 18,
            color: emphasized || focused
                ? AppColors.text.withValues(alpha: 0.88)
                : AppColors.text.withValues(alpha: 0.68),
          ),
        ),
      ),
    );
  }
}
