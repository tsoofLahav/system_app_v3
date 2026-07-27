import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../topic/topic_appearance.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../layout/file_layouts.dart';
import '../../ui/glass_surface.dart';
import '../../ui/overlay_dialog_shell.dart';
import '../../ui/overlay_dialog_style.dart';
import '../../ui/overlay_file_preview_card.dart';
import '../../ui/horizontal_carousel.dart';
import '../widgets/layout_picker_tile.dart';
import '../bring_file/bring_file_preview.dart';
import './arrange_layout_preview.dart';
import './file_arrange_draft.dart';
import './file_arrange_keyboard.dart';

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

  final _focusNode = FocusNode(debugLabel: 'fileArrangeOverlay');
  late final ScrollController _scrollController;
  late final HorizontalCarouselMetrics _metrics;
  late HorizontalCarouselController _carousel;
  late FileArrangeDraft _draft;
  ArrangeFocusZone _focusZone = ArrangeFocusZone.shown;
  ArrangeBottomFocus _bottomFocus =
      const ArrangeBottomFocus.layout(0);
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
      ordered: widget.state.orderedFilesFor(widget.topic, detail.files),
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
    _syncLayoutFocusIndex();
    _loadPreviews();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _carousel.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncLayoutFocusIndex() {
    _bottomFocus = ArrangeBottomFocus.forLayoutId(
      _draft.layoutId,
      _enabledLayoutIds(),
    );
  }

  List<String> _enabledLayoutIds() => enabledLayoutIds(_draft.ordered.length);

  void _setStateAndSyncLayout() {
    _syncLayoutFocusIndex();
    setState(() {});
  }

  int _centeredHiddenIndex() {
    final files = _draft.hidden;
    if (files.isEmpty) return 0;
    return _metrics.centeredIndex(
      viewportWidth: _overlayWidth,
      scrollOffset: _carousel.scrollOffset,
      itemCount: files.length,
    );
  }

  void _moveFocusUp() {
    setState(() {
      _focusZone = moveArrangeFocusUp(
        current: _focusZone,
        hasHidden: _draft.hidden.isNotEmpty,
      );
    });
  }

  void _moveFocusDown() {
    setState(() {
      _focusZone = moveArrangeFocusDown(
        current: _focusZone,
        hasHidden: _draft.hidden.isNotEmpty,
      );
    });
  }

  void _handleHorizontal(int delta) {
    switch (_focusZone) {
      case ArrangeFocusZone.layouts:
        final ids = _enabledLayoutIds();
        if (ids.isEmpty && delta != 0) {
          _bottomFocus = delta < 0
              ? const ArrangeBottomFocus.done()
              : const ArrangeBottomFocus.cancel();
          setState(() {});
          return;
        }
        _bottomFocus = _bottomFocus.step(layoutCount: ids.length, delta: delta);
        if (_bottomFocus.target == ArrangeBottomFocusTarget.layout) {
          _draft.setLayoutId(ids[_bottomFocus.layoutIndex]);
        }
        setState(() {});
      case ArrangeFocusZone.hidden:
        final files = _draft.hidden;
        if (files.isEmpty) return;
        final next = stepCarouselIndex(
          currentIndex: _centeredHiddenIndex(),
          itemCount: files.length,
          delta: delta,
        );
        _carousel.scrollToIndex(
          index: next,
          itemCount: files.length,
          viewportWidth: _overlayWidth,
        );
      case ArrangeFocusZone.shown:
        if (delta < 0) {
          if (!_draft.rotateShownRight()) return;
        } else {
          if (!_draft.rotateShownLeft()) return;
        }
        _setStateAndSyncLayout();
    }
  }

  void _transferBetweenSections() {
    if (_saving) return;
    switch (_focusZone) {
      case ArrangeFocusZone.hidden:
        if (_draft.hidden.isNotEmpty) {
          _onShowCenteredHidden(_overlayWidth);
        }
      case ArrangeFocusZone.shown:
        if (_draft.hide(0)) _setStateAndSyncLayout();
      case ArrangeFocusZone.layouts:
        return;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveFocusUp();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveFocusDown();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _handleHorizontal(spatialHorizontalDelta(
          isRtl: widget.state.isRtl,
          isLeftArrow: true,
        ));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _handleHorizontal(spatialHorizontalDelta(
          isRtl: widget.state.isRtl,
          isLeftArrow: false,
        ));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _transferBetweenSections();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _save();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (!_saving) Navigator.of(context).pop(false);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Widget _zoneChrome({
    required bool focused,
    required Widget child,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: focused
            ? Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                width: 1.5,
              )
            : null,
      ),
      child: child,
    );
  }

  Future<void> _loadPreviews() async {
    final files = [..._draft.ordered];
    final previews = <int, OverlayFilePreviewData>{
      for (final file in files) file.id: OverlayFilePreviewData.fromFile(file),
    };
    if (!mounted) return;
    setState(() {
      _previewsByFileId = previews;
      _previewsLoaded = true;
    });
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
    await widget.state.setLayoutForTopic(widget.topic, _draft.layoutId);
    // Prefer the topic state just wrote — the overlay still holds the snapshot
    // from when it opened, whose layout is the old one.
    final topic = widget.state.allTopics
            .where((t) => t.id == widget.topic.id)
            .firstOrNull ??
        widget.topic;
    final error = await widget.state.reorderTopicFiles(
      topic,
      ordered: _draft.ordered,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _onShownFileTap(AppFile file) {
    final index = _draft.shown.indexWhere((f) => f.id == file.id);
    if (index < 0) return;
    if (!_draft.moveShownToFirst(index)) return;
    _setStateAndSyncLayout();
  }

  void _onShownFileSecondaryTap(AppFile file) {
    final index = _draft.shown.indexWhere((f) => f.id == file.id);
    if (index < 0) return;
    if (!_draft.hide(index)) return;
    _setStateAndSyncLayout();
  }

  void _onShowCenteredHidden(double viewportWidth) {
    final files = _draft.hidden;
    if (files.isEmpty) return;
    final index = _metrics.centeredIndex(
      viewportWidth: viewportWidth,
      scrollOffset: _carousel.scrollOffset,
      itemCount: files.length,
    );
    if (!_draft.show(index)) return;
    _setStateAndSyncLayout();
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
      _onShowCenteredHidden(viewportWidth);
    }
    _tapCandidate = false;
    _tapDownPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final accent = TopicAppearance.accentFor(widget.topic);
    final hasHidden = _draft.hidden.isNotEmpty;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
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
                _zoneChrome(
                  focused: _focusZone == ArrangeFocusZone.shown,
                  child: SizedBox(
                    height: _mainPreviewHeight,
                    child: _draft.shown.isEmpty
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
                              '${_draft.layoutId}:${_draft.shown.map((f) => f.id).join(',')}',
                            ),
                            files: _draft.shown,
                            layoutId: _draft.layoutId,
                            topic: widget.topic,
                            accent: accent,
                            fileNameFor: (file) =>
                                widget.state.fileDisplayName(file.name),
                            onFileTap: _onShownFileTap,
                            onFileSecondaryTap: _onShownFileSecondaryTap,
                            previewsByFileId: _previewsByFileId,
                            previewsLoaded: _previewsLoaded,
                            strings: s,
                          ),
                  ),
                ),
                if (hasHidden) ...[
                  const SizedBox(height: 10),
                  Tooltip(
                    message: s['arrangeTapHiddenHint'],
                    child: Text(
                      s['arrangeOffScreen'],
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.textHint,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _zoneChrome(
                    focused: _focusZone == ArrangeFocusZone.hidden,
                    child: SizedBox(
                      height: _carouselHeight,
                      child: _buildHiddenCarousel(accent, s),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _zoneChrome(
                  focused: _focusZone == ArrangeFocusZone.layouts,
                  borderRadius: BorderRadius.circular(10),
                  child: _buildBottomBars(s),
                ),
              ],
            ),
          ),
        ),
    );
  }

  /// The files the layout has no room for. This strip is the only place they
  /// appear, so it is how the user gets one back on screen.
  Widget _buildHiddenCarousel(Color accent, AppStrings s) {
    final files = _draft.hidden;

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
    final enabledIds = _enabledLayoutIds();
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
                        FileLayouts.isAvailable(
                          layout.id,
                          _draft.ordered.length,
                        );
                    final enabledIndex = enabledIds.indexOf(layout.id);
                    final keyboardFocused = _focusZone == ArrangeFocusZone.layouts &&
                        _bottomFocus.target == ArrangeBottomFocusTarget.layout &&
                        _bottomFocus.layoutIndex == enabledIndex;
                    return LayoutPickerTile(
                      layoutId: layout.id,
                      label: s.layoutLabel(layout.id),
                      selected: _draft.layoutId == layout.id,
                      focused: keyboardFocused,
                      enabled: enabled,
                      compact: true,
                      iconWidth: 40,
                      iconHeight: 28,
                      onTap: enabled
                          ? () {
                              setState(() {
                                _draft.setLayoutId(layout.id);
                                _bottomFocus =
                                    ArrangeBottomFocus.layout(enabledIndex);
                                _focusZone = ArrangeFocusZone.layouts;
                              });
                            }
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
                focused: _focusZone == ArrangeFocusZone.layouts &&
                    _bottomFocus.target == ArrangeBottomFocusTarget.cancel,
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              ),
              _ChromeIconButton(
                tooltip: s['arrangeDone'],
                icon: AppIcons.check,
                focused: _focusZone == ArrangeFocusZone.layouts &&
                    _bottomFocus.target == ArrangeBottomFocusTarget.done,
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
