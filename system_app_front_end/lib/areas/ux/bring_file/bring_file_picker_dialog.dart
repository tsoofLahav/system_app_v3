import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/horizontal_carousel.dart';
import '../../ui/overlay_dialog_shell.dart';
import '../../ui/overlay_dialog_style.dart';
import '../../ui/overlay_file_preview_card.dart';
import '../arrange/file_arrange_keyboard.dart';
import '../topic/topic_appearance.dart';
import './bring_file_catalog.dart';
import './bring_file_preview.dart';
import './phone_bring_file_sheet.dart';

/// Search files from other topics. Choosing one visits that file on Home.
Future<void> showBringFilePicker({
  required BuildContext context,
  required AppState state,
}) async {
  final BrowseFileEntry? entry;
  if (isPhoneLayout) {
    entry = await showPhoneBringFileSheet(context: context, state: state);
  } else {
    entry = await showDialog<BrowseFileEntry>(
      context: context,
      barrierColor: OverlayDialogStyle.barrierColor,
      barrierDismissible: true,
      builder: (_) => BringFilePickerOverlay(state: state),
    );
  }
  if (entry == null || !context.mounted) return;
  await state.setBroughtFile(entry);
}

class BringFilePickerOverlay extends StatefulWidget {
  const BringFilePickerOverlay({super.key, required this.state});

  final AppState state;

  @override
  State<BringFilePickerOverlay> createState() => _BringFilePickerOverlayState();
}

class _BringFilePickerOverlayState extends State<BringFilePickerOverlay> {
  static const _itemWidth = 232.0;
  static const _itemSpacing = 16.0;
  static const _carouselHeight = 248.0;
  static const _searchMaxWidth = 420.0;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  late final HorizontalCarouselMetrics _metrics;
  late HorizontalCarouselController _carousel;

  List<BrowseFileEntry> _all = const [];
  List<BrowseFileEntry> _filtered = const [];
  var _loading = true;
  double _overlayWidth = 720;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _metrics = const HorizontalCarouselMetrics(
      itemWidth: _itemWidth,
      itemSpacing: _itemSpacing,
    );
    _carousel = HorizontalCarouselController(
      metrics: _metrics,
      scrollController: _scrollController,
      onChanged: () => setState(() {}),
    );
    _searchController.addListener(_applyFilter);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _carousel.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await _state.loadBringFileCatalog();
    if (!mounted) return;
    setState(() {
      _all = entries;
      _filtered = entries;
      _loading = false;
    });
  }

  void _applyFilter() {
    setState(() {
      _filtered = filterBringFileCatalog(
        _all,
        _searchController.text,
        topicLabel: _state.topicDisplayName,
        fileLabel: (file) => _state.fileDisplayName(file.name),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _filtered.isEmpty) return;
      _carousel.scrollToIndex(
        index: 0,
        itemCount: _filtered.length,
        viewportWidth: _overlayWidth,
      );
    });
  }

  int _centeredIndex() {
    if (_filtered.isEmpty) return 0;
    return _metrics.centeredIndex(
      viewportWidth: _overlayWidth,
      scrollOffset: _carousel.scrollOffset,
      itemCount: _filtered.length,
    );
  }

  void _choose(BrowseFileEntry entry) {
    Navigator.of(context).pop(entry);
  }

  void _chooseCentered() {
    if (_filtered.isEmpty) return;
    _choose(_filtered[_centeredIndex()]);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_searchFocus.hasFocus &&
        event.logicalKey != LogicalKeyboardKey.escape &&
        event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.arrowLeft &&
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _chooseCentered();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        if (_filtered.isEmpty) return KeyEventResult.handled;
        final delta = spatialHorizontalDelta(
          isRtl: _state.isRtl,
          isLeftArrow: event.logicalKey == LogicalKeyboardKey.arrowLeft,
        );
        final next = stepCarouselIndex(
          currentIndex: _centeredIndex(),
          itemCount: _filtered.length,
          delta: delta,
        );
        _carousel.scrollToIndex(
          index: next,
          itemCount: _filtered.length,
          viewportWidth: _overlayWidth,
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state.strings;
    final screenWidth = MediaQuery.sizeOf(context).width;
    _overlayWidth = (screenWidth - 40).clamp(640.0, 900.0);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: OverlayDialogShell(
        onDismiss: () => Navigator.of(context).pop(),
        child: SizedBox(
          width: _overlayWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s['bringFile'],
                style: AppTypography.metaStyle.copyWith(
                  color: AppColors.text.withValues(alpha: 0.78),
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: DialogFieldStyle.decoration(
                    hintText: s['bringFileSearchHint'],
                  ),
                  onSubmitted: (_) => _chooseCentered(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _carouselHeight,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              s['bringFileEmpty'],
                              style: AppTypography.metaStyle,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _buildCarousel(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarousel(AppStrings s) {
    return NotificationListener<ScrollEndNotification>(
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
            horizontal: _metrics.sidePadding(_overlayWidth),
            vertical: 4,
          ),
          itemCount: _filtered.length,
          separatorBuilder: (_, index) => const SizedBox(width: _itemSpacing),
          itemBuilder: (context, index) {
            final entry = _filtered[index];
            final emphasis = _metrics.emphasisForIndex(
              index: index,
              viewportWidth: _overlayWidth,
              scrollOffset: _carousel.scrollOffset,
            );
            final style = carouselEmphasisStyle(emphasis);
            final accent = TopicAppearance.accentFor(entry.topic);
            return Transform.translate(
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
                      fileName: _state.fileDisplayName(entry.file.name),
                      accent: accent,
                      topicLabel: _state.topicDisplayName(entry.topic),
                      preview: OverlayFilePreviewData.fromFile(entry.file),
                      previewsLoaded: true,
                      strings: s,
                      emphasized: emphasis > 0.7,
                      onTap: () => _choose(entry),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
  }
}
