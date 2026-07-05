import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/file_layouts.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../../design_system/bilingual_layout.dart';
import '../../features/shell/app_bottom_bar.dart';
import '../../shared/widgets/topic_emoji.dart';
import '../../shared/widgets/main_pane_loader.dart';
import 'archive_file_grid.dart';
import 'archive_file_preview.dart';

class ArchiveTopicView extends StatefulWidget {
  const ArchiveTopicView({super.key, required this.state});

  final AppState state;

  @override
  State<ArchiveTopicView> createState() => _ArchiveTopicViewState();
}

class _ArchiveTopicViewState extends State<ArchiveTopicView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  var _searchExpanded = false;
  var _loadMoreScheduled = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant ArchiveTopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.selectedArchiveTopic?.id !=
        widget.state.selectedArchiveTopic?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _collapseSearch();
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    if (!oldWidget.state.archiveDeleteMode && widget.state.archiveDeleteMode) {
      _collapseSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _searchController.removeListener(_onSearchChanged);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    state.onArchiveSearchQueryChanged(_searchController.text);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadMoreScheduled) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels < position.maxScrollExtent - 280) return;

    final canLoadMore = state.archiveIsSearching
        ? state.archiveSearchHasMore
        : state.archiveHasMore;
    if (!canLoadMore || state.archiveIsFetchingMore) return;

    _loadMoreScheduled = true;
    state.loadMoreArchiveContent().whenComplete(() {
      _loadMoreScheduled = false;
    });
  }

  void _expandSearch() {
    if (state.archiveDeleteMode) return;
    setState(() => _searchExpanded = true);
  }

  void _collapseSearch() {
    if (!_searchExpanded && _searchController.text.isEmpty) return;
    setState(() => _searchExpanded = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
      }
      state.onArchiveSearchQueryChanged('');
    });
  }

  AppFile? _previewFile(List<AppFile> files) {
    if (files.isEmpty) return null;
    final selected = state.selectedArchiveFile;
    if (selected != null && files.any((file) => file.id == selected.id)) {
      return selected;
    }
    return files.first;
  }

  double _previewHeight(BuildContext context, EdgeInsets canvasPadding) {
    final slotHeight = FileLayouts.primarySlotHeight(
      context,
      canvasPaddingTop: canvasPadding.top,
      canvasPaddingBottom: canvasPadding.bottom,
      reservedBelow: FileLayouts.secondarySectionReserve + 80,
    );
    return math.min(400, slotHeight * 0.68);
  }

  @override
  Widget build(BuildContext context) {
    final topic = state.selectedArchiveTopic;
    if (topic == null) {
      return TopicCanvasBackground(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: AppSpacing.canvasPadding,
            child: Text(state.strings['selectTopic']),
          ),
        ),
      );
    }

    final accent = TopicAppearance.colorFromHex(topic.color);
    final loading =
        state.archiveInitialLoading && state.archiveFilesForTopic.isEmpty;
    final canvasPadding = AppSpacing.canvasPadding.copyWith(
      top: AppSpacing.canvasPadding.top + AppTopicHeaderMetrics.scrollTopInset,
      bottom: AppSpacing.canvasPadding.bottom + AppBottomBarMetrics.scrollInset,
    );
    final previewHeight = _previewHeight(context, canvasPadding);
    final files = state.displayArchiveFiles;
    final previewFile = _previewFile(files);
    final deleteMode = state.archiveDeleteMode;
    final s = state.strings;

    return TopicCanvasBackground(
      accent: accent,
      isMain: topic.isMain,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: canvasPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: MainPaneLoader(compact: true),
                    )
                  else if (state.archiveTotalCount == 0 &&
                      !state.archiveIsSearching)
                    Text(s['archiveNoFiles'], style: AppTypography.noteBodyStyle)
                  else if (files.isEmpty &&
                      state.archiveIsSearching &&
                      !state.archiveSearchLoading)
                    Text(
                      s['archiveNoSearchResults'],
                      style: AppTypography.noteBodyStyle,
                    )
                  else ...[
                    if (deleteMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          s['archiveDeleteSelect'],
                          style: AppTypography.metaStyle.copyWith(
                            color: AppColors.textHint,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                    if (!deleteMode && previewFile != null)
                      ArchiveFilePreview(
                        topic: topic,
                        file: previewFile,
                        blocks: state.archiveBlocksByFileId[previewFile.id] ??
                            const [],
                        tasksByBlockId: state.archiveTasksByBlockId,
                        state: state,
                        height: previewHeight,
                      )
                    else if (!deleteMode)
                      _EmptyArchivePreview(
                        height: previewHeight,
                        topic: topic,
                      ),
                    if (!deleteMode) const SizedBox(height: 16),
                    ArchiveFileGrid(
                      files: files,
                      state: state,
                      selectedFileId: previewFile?.id,
                      onSelect: state.selectArchiveFile,
                      deleteMode: deleteMode,
                      markedForDelete: state.archiveDeleteSelection,
                      onToggleDelete: state.toggleArchiveDeleteSelection,
                    ),
                    if (state.archiveIsFetchingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: MainPaneLoader(compact: true),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ArchiveTopicHeader(
              topic: topic,
              accent: accent,
              state: state,
              searchExpanded: _searchExpanded,
              searchEnabled: !state.archiveDeleteMode,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              onExpandSearch: _expandSearch,
              onCollapseSearch: _collapseSearch,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyArchivePreview extends StatelessWidget {
  const _EmptyArchivePreview({required this.height, required this.topic});

  final double height;
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final accent = TopicAppearance.colorFromHex(topic.color);
    return SizedBox(
      height: height,
      child: NoteCard(
        topicAccent: accent,
        fileType: 'note',
        isMainTopic: topic.isMain,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ArchiveTopicHeader extends StatelessWidget {
  const _ArchiveTopicHeader({
    required this.topic,
    required this.accent,
    required this.state,
    required this.searchExpanded,
    required this.searchEnabled,
    required this.searchController,
    required this.searchFocusNode,
    required this.onExpandSearch,
    required this.onCollapseSearch,
  });

  final Topic topic;
  final Color accent;
  final AppState state;
  final bool searchExpanded;
  final bool searchEnabled;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onExpandSearch;
  final VoidCallback onCollapseSearch;

  @override
  Widget build(BuildContext context) {
    final isMain = topic.isMain;
    final s = state.strings;
    final veilTint = Color.alphaBlend(
      (isMain ? AppColors.text : accent).withValues(
        alpha: isMain ? 0.02 : 0.08,
      ),
      Colors.white,
    );

    return SizedBox(
      height: AppTopicHeaderMetrics.scrollTopInset,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      veilTint.withValues(alpha: 0.86),
                      veilTint.withValues(alpha: 0.52),
                      veilTint.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.58, 1],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTopicHeaderMetrics.horizontalMargin,
              AppTopicHeaderMetrics.floatMargin,
              AppTopicHeaderMetrics.horizontalMargin,
              0,
            ),
            child: SizedBox(
              height: AppTopicHeaderMetrics.headerHeight,
              child: StartTrailingRow(
                crossAxisAlignment: CrossAxisAlignment.center,
                gap: AppTopicHeaderMetrics.headerGap,
                content: Row(
                  children: [
                    if (!isMain) ...[
                      TopicEmoji(value: topic.icon, size: 16),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        state.topicDisplayName(topic),
                        style: AppTypography.noteTitleStyle.copyWith(
                          fontSize: 15,
                          height: 1.2,
                          color: AppColors.text.withValues(alpha: 0.94),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ],
                ),
                trailing: _ArchiveSearchBar(
                  expanded: searchExpanded,
                  enabled: searchEnabled,
                  controller: searchController,
                  focusNode: searchFocusNode,
                  hintText: s['archiveSearchHint'],
                  onExpand: onExpandSearch,
                  onCollapse: onCollapseSearch,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveSearchBar extends StatefulWidget {
  const _ArchiveSearchBar({
    required this.expanded,
    required this.enabled,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onExpand,
    required this.onCollapse,
  });

  final bool expanded;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  @override
  State<_ArchiveSearchBar> createState() => _ArchiveSearchBarState();
}

class _ArchiveSearchBarState extends State<_ArchiveSearchBar>
    with SingleTickerProviderStateMixin {
  static const _collapsedSize = AppTopicHeaderMetrics.addButtonSize;
  static const _expandedWidth = 216.0;

  late final AnimationController _widthController;
  late final Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    _widthController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.expanded ? 1 : 0,
    );
    _widthAnimation = Tween<double>(
      begin: _collapsedSize,
      end: _expandedWidth,
    ).animate(
      CurvedAnimation(
        parent: _widthController,
        curve: Curves.easeOutCubic,
      ),
    );
    _widthController.addStatusListener(_onAnimStatus);
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.expanded && mounted) {
      widget.focusNode.requestFocus();
    }
  }

  @override
  void didUpdateWidget(covariant _ArchiveSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (widget.expanded) {
      _widthController.forward();
      return;
    }
    widget.focusNode.unfocus();
    _widthController.reverse();
  }

  @override
  void dispose() {
    _widthController.removeStatusListener(_onAnimStatus);
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: AnimatedBuilder(
        animation: _widthAnimation,
        builder: (context, _) {
          final width = _widthAnimation.value;
          final showField = width > _collapsedSize + 8;

          return Container(
            width: width,
            height: _collapsedSize,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
              border: Border.all(
                color: AppColors.noteBorder.withValues(alpha: 0.55),
                width: AppColors.filePaneBorderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.text.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final iconSize = constraints.maxHeight;
                return Row(
                  children: [
                    if (showField)
                      Expanded(
                        child: TextField(
                          key: const ValueKey('archive-search-field'),
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          textAlign: TextAlign.start,
                          style: AppTypography.noteTitleStyle.copyWith(
                            fontSize: 13,
                            height: 1.2,
                            color: AppColors.text.withValues(alpha: 0.94),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.hintText,
                            hintStyle: AppTypography.noteTitleStyle.copyWith(
                              fontSize: 13,
                              color: AppColors.textHint.withValues(
                                alpha: 0.75,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsetsDirectional.only(start: 12),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: _SearchIconButton(
                        icon: showField ? AppIcons.close : AppIcons.search,
                        enabled: enabled,
                        onPressed: !enabled
                            ? null
                            : showField
                            ? widget.onCollapse
                            : widget.onExpand,
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Center(
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? AppColors.text.withValues(alpha: 0.78)
                : AppColors.textHint.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}
