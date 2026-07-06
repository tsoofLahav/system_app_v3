import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/file_layouts.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/overlay_dialog_shell.dart';
import '../../design_system/overlay_dialog_style.dart';
import '../../design_system/overlay_file_preview_card.dart';
import '../../design_system/horizontal_carousel.dart';
import '../../shared/widgets/layout_picker_tile.dart';
import '../bring_file/bring_file_preview.dart';
import 'arrange_layout_preview.dart';
import 'file_arrange_draft.dart';

Future<bool?> showFileArrangeOverlay(BuildContext context, AppState state) {
  final topic = state.selectedDetail?.topic;
  if (topic == null) return Future.value(null);

  return showDialog<bool>(
    context: context,
    barrierColor: OverlayDialogStyle.barrierColor,
    barrierDismissible: true,
    builder: (_) => FileArrangeOverlay(state: state, topic: topic),
  );
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
  static const _carouselItemWidth = 200.0;
  static const _carouselItemSpacing = 14.0;
  static const _carouselHeight = 168.0;
  static const _bottomBarHeight = 42.0;
  static const _tapSlop = 12.0;

  late final ScrollController _scrollController;
  late final HorizontalCarouselMetrics _metrics;
  late HorizontalCarouselController _carousel;
  late FileArrangeDraft _draft;
  bool _saving = false;
  bool _tapCandidate = false;
  Offset? _tapDownPosition;
  Map<int, OverlayFilePreviewData> _previewsByFileId = {};
  bool _previewsLoaded = false;

  @override
  void initState() {
    super.initState();
    final detail = widget.state.selectedDetail!;
    _draft = FileArrangeDraft(
      main: widget.state.mainFilesFor(widget.topic, detail.files),
      additional: widget.state.secondaryFilesFor(widget.topic, detail.files),
      layoutId: widget.state.layoutFor(widget.topic),
    );
    _scrollController = ScrollController();
    _metrics = const HorizontalCarouselMetrics(
      itemWidth: _carouselItemWidth,
      itemSpacing: _carouselItemSpacing,
    );
    _carousel = HorizontalCarouselController(
      metrics: _metrics,
      scrollController: _scrollController,
      onChanged: () => setState(() {}),
    );
    _loadPreviews();
  }

  @override
  void dispose() {
    _carousel.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreviews() async {
    final files = [..._draft.main, ..._draft.additional];
    if (files.isEmpty) return;
    try {
      final previews = await widget.state.loadBringFilePreviews(files);
      if (!mounted) return;
      setState(() {
        _previewsByFileId = previews;
        _previewsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewsLoaded = true);
    }
  }

  double get _overlayWidth {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth - 40).clamp(560.0, 720.0);
  }

  double get _mainPreviewHeight {
    // Taller than wide — main area dominates vertically.
    return (_overlayWidth * 0.62).clamp(300.0, 420.0);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    widget.state.setLayoutForTopic(widget.topic, _draft.layoutId);
    final error = await widget.state.reorderTopicFiles(
      widget.topic,
      _draft.ordered,
      _draft.mainCount,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _onMainFileTap(AppFile file) {
    final index = _draft.main.indexWhere((f) => f.id == file.id);
    if (index < 0) return;
    if (!_draft.moveMainToFirst(index)) return;
    setState(() {});
  }

  void _onMainFileSecondaryTap(AppFile file) {
    final index = _draft.main.indexWhere((f) => f.id == file.id);
    if (index < 0) return;
    if (!_draft.demoteFromMain(index)) return;
    setState(() {});
  }

  void _onPromoteCenteredAdditional(double viewportWidth) {
    final files = _draft.additional;
    if (files.isEmpty) return;
    final index = _metrics.centeredIndex(
      viewportWidth: viewportWidth,
      scrollOffset: _carousel.scrollOffset,
      itemCount: files.length,
    );
    if (!_draft.promoteFromAdditional(index)) return;
    setState(() {});
  }

  void _onCarouselPointerDown(PointerDownEvent event) {
    _tapCandidate = true;
    _tapDownPosition = event.position;
  }

  void _onCarouselPointerMove(PointerMoveEvent event) {
    final origin = _tapDownPosition;
    if (!_tapCandidate || origin == null) return;
    if ((event.position - origin).distance > _tapSlop) {
      _tapCandidate = false;
    }
  }

  void _onCarouselPointerUp(double viewportWidth) {
    if (_tapCandidate) {
      _onPromoteCenteredAdditional(viewportWidth);
    }
    _tapCandidate = false;
    _tapDownPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final accent = TopicAppearance.accentFor(widget.topic);
    final hasAdditional = _draft.additional.isNotEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_saving) return;
          if (hasAdditional) {
            _onPromoteCenteredAdditional(_overlayWidth);
          } else {
            _save();
          }
        },
      },
      child: OverlayDialogShell(
        onDismiss: _saving ? null : () => Navigator.of(context).pop(false),
        child: SizedBox(
          width: _overlayWidth,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s['arrangeFiles'],
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.text.withValues(alpha: 0.78),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: _mainPreviewHeight,
                  child: _draft.main.isEmpty
                      ? Center(
                          child: Text(
                            s['noFilesYet'],
                            style: AppTypography.noteBodyStyle.copyWith(
                              color: AppColors.noteHint,
                            ),
                          ),
                        )
                      : ArrangeLayoutPreview(
                          key: ValueKey(
                            '${_draft.layoutId}:${_draft.main.map((f) => f.id).join(',')}',
                          ),
                          files: _draft.main,
                          layoutId: _draft.layoutId,
                          topic: widget.topic,
                          accent: accent,
                          fileNameFor: (file) =>
                              widget.state.fileDisplayName(file.name),
                          onFileTap: _onMainFileTap,
                          onFileSecondaryTap: _onMainFileSecondaryTap,
                          previewsByFileId: _previewsByFileId,
                          previewsLoaded: _previewsLoaded,
                          strings: s,
                        ),
                ),
                if (hasAdditional) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: _carouselHeight,
                    child: _buildAdditionalCarousel(accent, s),
                  ),
                ],
                const SizedBox(height: 14),
                _buildBottomBars(s),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildAdditionalCarousel(Color accent, AppStrings s) {
    final files = _draft.additional;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onCarouselPointerDown,
      onPointerMove: _onCarouselPointerMove,
      onPointerUp: (_) => _onCarouselPointerUp(_overlayWidth),
      onPointerCancel: (_) {
        _tapCandidate = false;
        _tapDownPosition = null;
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          if (!_carousel.isSnapping) {
            _carousel.snapToNearest(files.length);
          }
          return false;
        },
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(
            horizontal: _metrics.sidePadding(_overlayWidth),
            vertical: 4,
          ),
          itemCount: files.length,
          separatorBuilder: (_, index) =>
              const SizedBox(width: _carouselItemSpacing),
          itemBuilder: (context, index) {
            final file = files[index];
            final emphasis = _metrics.emphasisForIndex(
              index: index,
              viewportWidth: _overlayWidth,
              scrollOffset: _carousel.scrollOffset,
            );
            final style = carouselEmphasisStyle(emphasis);

            return IgnorePointer(
              child: Transform.translate(
                offset: Offset(0, style.lift),
                child: Transform.scale(
                  scale: style.scale,
                  child: Opacity(
                    opacity: style.opacity,
                    child: SizedBox(
                      width: _carouselItemWidth,
                      height: _carouselHeight,
                      child: OverlayFilePreviewCard(
                        file: file,
                        topic: widget.topic,
                        fileName: widget.state.fileDisplayName(file.name),
                        accent: accent,
                        preview:
                            _previewsByFileId[file.id] ?? OverlayFilePreviewData.empty,
                        previewsLoaded: _previewsLoaded,
                        strings: s,
                        padding: const EdgeInsets.all(12),
                        titleFontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBars(AppStrings s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassBarSegment(
          height: _bottomBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < FileLayouts.all.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Builder(
                  builder: (context) {
                    final layout = FileLayouts.all[i];
                    final enabled =
                        FileLayouts.isAvailable(layout.id, _draft.mainCount);
                    return LayoutPickerTile(
                      layoutId: layout.id,
                      label: s.layoutLabel(layout.id),
                      selected: _draft.layoutId == layout.id,
                      enabled: enabled,
                      compact: true,
                      iconWidth: 40,
                      iconHeight: 28,
                      onTap: enabled
                          ? () => setState(() => _draft.setLayoutId(layout.id))
                          : null,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        GlassBarSegment(
          height: _bottomBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChromeIconButton(
                tooltip: s['cancel'],
                icon: AppIcons.close,
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              ),
              _ChromeIconButton(
                tooltip: s['arrangeDone'],
                icon: AppIcons.check,
                onPressed: _saving ? null : _save,
                emphasized: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(
          icon,
          size: 18,
          color: emphasized
              ? AppColors.text.withValues(alpha: 0.88)
              : AppColors.text.withValues(alpha: 0.68),
        ),
      ),
    );
  }
}
