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
import 'file_arrange_keyboard.dart';

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
  ArrangeFocusZone _focusZone = ArrangeFocusZone.main;
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
    final ids = enabledLayoutIds(_draft.mainCount);
    _bottomFocus = ArrangeBottomFocus.forLayoutId(_draft.layoutId, ids);
  }

  List<String> _enabledLayoutIds() => enabledLayoutIds(_draft.mainCount);

  void _setStateAndSyncLayout() {
    _syncLayoutFocusIndex();
    setState(() {});
  }

  int _centeredAdditionalIndex() {
    final files = _draft.additional;
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
        hasAdditional: _draft.additional.isNotEmpty,
      );
    });
  }

  void _moveFocusDown() {
    setState(() {
      _focusZone = moveArrangeFocusDown(
        current: _focusZone,
        hasAdditional: _draft.additional.isNotEmpty,
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
      case ArrangeFocusZone.additional:
        final files = _draft.additional;
        if (files.isEmpty) return;
        final next = stepCarouselIndex(
          currentIndex: _centeredAdditionalIndex(),
          itemCount: files.length,
          delta: delta,
        );
        _carousel.scrollToIndex(
          index: next,
          itemCount: files.length,
          viewportWidth: _overlayWidth,
        );
      case ArrangeFocusZone.main:
        if (delta < 0) {
          if (!_draft.rotateMainRight()) return;
        } else {
          if (!_draft.rotateMainLeft()) return;
        }
        _setStateAndSyncLayout();
    }
  }

  void _transferBetweenSections() {
    if (_saving) return;
    switch (_focusZone) {
      case ArrangeFocusZone.additional:
        if (_draft.additional.isNotEmpty) {
          _onPromoteCenteredAdditional(_overlayWidth);
        }
      case ArrangeFocusZone.main:
        if (_draft.main.isNotEmpty && _draft.demoteFromMain(0)) {
          _setStateAndSyncLayout();
        }
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
    _setStateAndSyncLayout();
  }

  void _onMainFileSecondaryTap(AppFile file) {
    final index = _draft.main.indexWhere((f) => f.id == file.id);
    if (index < 0) return;
    if (!_draft.demoteFromMain(index)) return;
    _setStateAndSyncLayout();
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
                  focused: _focusZone == ArrangeFocusZone.main,
                  child: SizedBox(
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
                ),
                if (hasAdditional) ...[
                  const SizedBox(height: 14),
                  _zoneChrome(
                    focused: _focusZone == ArrangeFocusZone.additional,
                    child: SizedBox(
                      height: _carouselHeight,
                      child: _buildAdditionalCarousel(accent, s),
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
                        FileLayouts.isAvailable(layout.id, _draft.mainCount);
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
