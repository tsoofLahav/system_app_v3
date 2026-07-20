import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/browse/bring_file_catalog.dart';
import '../../core/platform/app_form_factor.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/overlay_dialog_shell.dart';
import '../../design_system/overlay_dialog_style.dart';
import '../../features/bring_file/bring_file_preview.dart';
import '../../design_system/overlay_file_preview_card.dart';
import '../../design_system/horizontal_carousel.dart';
import '../arrange/file_arrange_keyboard.dart';
import 'phone_bring_file_sheet.dart';

Future<BrowseFileEntry?> showBringFilePicker(
  BuildContext context,
  AppState state,
) {
  if (isPhoneLayout) {
    return showPhoneBringFileSheet(context, state);
  }
  return showBringFilePickerDialog(context, state);
}

Future<BrowseFileEntry?> showBringFilePickerDialog(
  BuildContext context,
  AppState state,
) {
  return showDialog<BrowseFileEntry>(
    context: context,
    barrierColor: OverlayDialogStyle.barrierColor,
    barrierDismissible: true,
    builder: (_) => BringFilePickerDialog(state: state),
  );
}

class BringFilePickerDialog extends StatefulWidget {
  const BringFilePickerDialog({super.key, required this.state});

  final AppState state;

  @override
  State<BringFilePickerDialog> createState() => _BringFilePickerDialogState();
}

class _BringFilePickerDialogState extends State<BringFilePickerDialog> {
  static const _itemWidth = 232.0;
  static const _itemSpacing = 16.0;
  static const _carouselHeight = 248.0;
  static const _searchBarHeight = 44.0;
  static const _searchMaxWidth = 420.0;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final ScrollController _scrollController;
  late final HorizontalCarouselMetrics _metrics;
  late HorizontalCarouselController _carousel;

  List<BrowseFileEntry> _entries = [];
  List<BrowseFileEntry> _filtered = [];
  Map<int, OverlayFilePreviewData> _previewsByFileId = {};
  bool _loading = true;
  bool _previewsLoaded = false;
  String? _error;
  bool _tapCandidate = false;
  Offset? _tapDownPosition;
  double _carouselViewportWidth = 800;

  static const _tapSlop = 12.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _metrics = const HorizontalCarouselMetrics(
      itemWidth: _itemWidth,
      itemSpacing: _itemSpacing,
    );
    _carousel = HorizontalCarouselController(
      metrics: _metrics,
      scrollController: _scrollController,
      onChanged: () => setState(() {}),
    );
    _searchFocusNode.onKeyEvent = _onSearchKeyEvent;
    _loadCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.onKeyEvent = null;
    _carousel.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final entries = await widget.state.loadBringFileCatalog();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _filtered = entries;
        _loading = false;
      });
      _loadPreviews(entries);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadPreviews(List<BrowseFileEntry> entries) async {
    if (entries.isEmpty) return;
    try {
      final previews = await widget.state.loadBringFilePreviews(
        entries.map((entry) => entry.file).toList(growable: false),
      );
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

  void _onQueryChanged(String query) {
    setState(() {
      _filtered = filterBringFileCatalog(
        _entries,
        query,
        topicLabel: widget.state.topicDisplayName,
        fileLabel: (file) => widget.state.fileDisplayName(file.name),
      );
    });
  }

  void _close() {
    Navigator.of(context).pop();
  }

  void _selectEntry(BrowseFileEntry entry) {
    Navigator.of(context).pop(entry);
  }

  int? _centeredIndex(double viewportWidth) {
    if (_filtered.isEmpty) return null;
    return _metrics.centeredIndex(
      viewportWidth: viewportWidth,
      scrollOffset: _carousel.scrollOffset,
      itemCount: _filtered.length,
    );
  }

  void _selectCenteredFile(double viewportWidth) {
    final index = _centeredIndex(viewportWidth);
    if (index == null) return;
    _selectEntry(_filtered[index]);
  }

  void _scrollCarousel(int delta, double viewportWidth) {
    if (_filtered.isEmpty) return;
    final current = _centeredIndex(viewportWidth) ?? 0;
    final next = stepCarouselIndex(
      currentIndex: current,
      itemCount: _filtered.length,
      delta: delta,
    );
    _carousel.scrollToIndex(
      index: next,
      itemCount: _filtered.length,
      viewportWidth: viewportWidth,
    );
  }

  KeyEventResult _onSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final carouselWidth = _carouselViewportWidth;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _scrollCarousel(
          spatialHorizontalDelta(
            isRtl: widget.state.isRtl,
            isLeftArrow: true,
          ),
          carouselWidth,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _scrollCarousel(
          spatialHorizontalDelta(
            isRtl: widget.state.isRtl,
            isLeftArrow: false,
          ),
          carouselWidth,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
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
      _selectCenteredFile(viewportWidth);
    }
    _tapCandidate = false;
    _tapDownPosition = null;
  }

  double _carouselWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth - 24).clamp(620.0, 980.0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final carouselWidth = _carouselWidth(context);
    _carouselViewportWidth = carouselWidth;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_filtered.isEmpty || _loading) return;
          _selectCenteredFile(carouselWidth);
        },
      },
      child: OverlayDialogShell(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 64),
        onDismiss: _close,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
                child: _BringFileSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  hintText: s['bringFileSearchHint'],
                  title: s['bringFile'],
                  dismissTooltip: s['cancel'],
                  onChanged: _onQueryChanged,
                  onDismiss: _close,
                  onSubmit: () {
                    if (_filtered.isEmpty || _loading) return;
                    _selectCenteredFile(carouselWidth);
                  },
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: carouselWidth,
                height: _carouselHeight + 16,
                child: _buildCarouselBody(s),
              ),
            ],
        ),
      ),
    );
  }

  Widget _buildCarouselBody(AppStrings s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          s['bringFileEmpty'],
          style: AppTypography.noteBodyStyle.copyWith(
            color: AppColors.noteHint,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final sidePadding = _metrics.sidePadding(viewportWidth);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onCarouselPointerDown,
          onPointerMove: _onCarouselPointerMove,
          onPointerUp: (_) => _onCarouselPointerUp(viewportWidth),
          onPointerCancel: (_) {
            _tapCandidate = false;
            _tapDownPosition = null;
          },
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              if (!_carousel.isSnapping) {
                _carousel.snapToNearest(_filtered.length);
              }
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(
                horizontal: sidePadding,
                vertical: 8,
              ),
              itemCount: _filtered.length,
              separatorBuilder: (_, index) =>
                  const SizedBox(width: _itemSpacing),
              itemBuilder: (context, index) {
                final entry = _filtered[index];
                final emphasis = _metrics.emphasisForIndex(
                  index: index,
                  viewportWidth: viewportWidth,
                  scrollOffset: _carousel.scrollOffset,
                );
                final style = carouselEmphasisStyle(emphasis);
                final accent = TopicAppearance.accentFor(entry.topic);
                final preview =
                    _previewsByFileId[entry.file.id] ?? OverlayFilePreviewData.empty;

                return IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(0, style.lift),
                    child: Transform.scale(
                      scale: style.scale,
                      child: Opacity(
                        opacity: style.opacity,
                        child: SizedBox(
                          width: _itemWidth,
                          height: _carouselHeight,
                          child: OverlayFilePreviewCard(
                            file: entry.file,
                            topic: entry.topic,
                            fileName: widget.state
                                .fileDisplayName(entry.file.name),
                            topicLabel: widget.state
                                .topicDisplayName(entry.topic),
                            accent: accent,
                            preview: preview,
                            previewsLoaded: _previewsLoaded,
                            strings: widget.state.strings,
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
      },
    );
  }
}

class _BringFileSearchBar extends StatelessWidget {
  const _BringFileSearchBar({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.title,
    required this.dismissTooltip,
    required this.onChanged,
    required this.onDismiss,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String title;
  final String dismissTooltip;
  final ValueChanged<String> onChanged;
  final VoidCallback onDismiss;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.text.withValues(alpha: 0.72),
            fontSize: 11,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        GlassBarSegment(
          height: _BringFilePickerDialogState._searchBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const AppIcon(AppIcons.search, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: AppTypography.noteBodyStyle.copyWith(fontSize: 13),
                  decoration: AppTypography.noteInputDecoration(
                    hint: hintText,
                    fontSize: 13,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: 4),
              _SearchDismissButton(
                tooltip: dismissTooltip,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchDismissButton extends StatelessWidget {
  const _SearchDismissButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              AppIcons.close,
              size: 16,
              color: AppColors.text.withValues(alpha: 0.62),
            ),
          ),
        ),
      ),
    );
  }
}

