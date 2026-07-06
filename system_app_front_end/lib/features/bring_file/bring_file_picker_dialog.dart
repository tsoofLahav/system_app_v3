import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/browse/bring_file_catalog.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<BrowseFileEntry?> showBringFilePickerDialog(
  BuildContext context,
  AppState state,
) {
  return showDialog<BrowseFileEntry>(
    context: context,
    barrierColor: Colors.transparent,
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
  final _scrollController = ScrollController();

  List<BrowseFileEntry> _entries = [];
  List<BrowseFileEntry> _filtered = [];
  Map<int, List<String>> _previewLinesByFileId = {};
  bool _loading = true;
  bool _previewsLoaded = false;
  String? _error;
  double _scrollOffset = 0;
  bool _isSnapping = false;
  bool _tapCandidate = false;
  Offset? _tapDownPosition;

  static const _snapEpsilon = 1.5;
  static const _tapSlop = 12.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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
        _previewLinesByFileId = previews;
        _previewsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewsLoaded = true);
    }
  }

  void _onScroll() {
    setState(() => _scrollOffset = _scrollController.offset);
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

    final sidePadding = _sidePadding(viewportWidth);
    final stride = _itemWidth + _itemSpacing;
    final center = _scrollOffset + viewportWidth / 2;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _filtered.length; i++) {
      final itemCenter = sidePadding + i * stride + _itemWidth / 2;
      final distance = (itemCenter - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  void _selectCenteredFile(double viewportWidth) {
    final index = _centeredIndex(viewportWidth);
    if (index == null) return;
    _selectEntry(_filtered[index]);
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

  void _snapToNearest() {
    if (_isSnapping || !_scrollController.hasClients || _filtered.isEmpty) {
      return;
    }

    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final sidePadding = _sidePadding(viewport);
    final stride = _itemWidth + _itemSpacing;
    final currentOffset = position.pixels;
    final bestIndex = _centeredIndex(viewport) ?? 0;
    final target =
        (sidePadding + bestIndex * stride + _itemWidth / 2 - viewport / 2)
            .clamp(0.0, position.maxScrollExtent);
    if ((target - currentOffset).abs() < _snapEpsilon) return;

    _isSnapping = true;
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          _isSnapping = false;
        });
  }

  double _sidePadding(double viewportWidth) {
    return ((viewportWidth - _itemWidth) / 2).clamp(0.0, double.infinity);
  }

  double _emphasisForIndex(int index, double viewportWidth) {
    final sidePadding = _sidePadding(viewportWidth);
    final stride = _itemWidth + _itemSpacing;
    final itemCenter = sidePadding + index * stride + _itemWidth / 2;
    final viewportCenter = _scrollOffset + viewportWidth / 2;
    final distance = (itemCenter - viewportCenter).abs();
    return (1 - (distance / (_itemWidth * 1.35)).clamp(0.0, 1.0)).toDouble();
  }

  double _carouselWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth - 24).clamp(620.0, 980.0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final carouselWidth = _carouselWidth(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_filtered.isEmpty || _loading) return;
          _selectCenteredFile(carouselWidth);
        },
      },
      child: Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 64),
        child: Align(
          alignment: Alignment.center,
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
        final sidePadding = _sidePadding(viewportWidth);
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
              if (!_isSnapping) _snapToNearest();
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
                final emphasis = _emphasisForIndex(index, viewportWidth);
                final scale = 0.86 + (0.14 * emphasis);
                final opacity = 0.82 + (0.18 * emphasis);
                final lift = (1 - emphasis) * 8;
                final accent = TopicAppearance.colorFromHex(entry.topic.color);
                final previewLines =
                    _previewLinesByFileId[entry.file.id] ?? const [];

                return IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: _CarouselCard(
                          entry: entry,
                          accent: accent,
                          state: widget.state,
                          previewLines: previewLines,
                          previewsLoaded: _previewsLoaded,
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

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({
    required this.entry,
    required this.accent,
    required this.state,
    required this.previewLines,
    required this.previewsLoaded,
  });

  final BrowseFileEntry entry;
  final Color accent;
  final AppState state;
  final List<String> previewLines;
  final bool previewsLoaded;

  static final _cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.11),
      blurRadius: 20,
      offset: const Offset(0, 5),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _BringFilePickerDialogState._itemWidth,
      height: _BringFilePickerDialogState._carouselHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: _cardShadow,
        ),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          tintColor: accent,
          tintOpacity: 0.24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.topicDisplayName(entry.topic),
                style: AppTypography.metaStyle.copyWith(
                  color: accent.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                state.fileDisplayName(entry.file.name),
                style: AppTypography.noteTitleStyle.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _buildPreviewBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewBody() {
    if (!previewsLoaded) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          state.strings['bringFilePreviewLoading'],
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.noteHint.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      );
    }
    if (previewLines.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          state.strings['bringFilePreviewEmpty'],
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.noteHint.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: previewLines.length,
      separatorBuilder: (_, index) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final line = previewLines[index];
        final isTask = line.startsWith('• ');
        return Text(
          line,
          style: AppTypography.noteBodyStyle.copyWith(
            fontSize: 11,
            height: 1.35,
            color: AppColors.text.withValues(alpha: isTask ? 0.72 : 0.78),
          ),
          maxLines: isTask ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
