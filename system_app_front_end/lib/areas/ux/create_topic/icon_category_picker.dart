import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/dialog_field_style.dart';

/// WhatsApp-style emoji picker (standard categories + full emoji set).
///
/// Two keyboard panes — the grid and the section bar — each with a focus
/// ring. Tab moves between them; arrows move inside the focused pane.
class IconCategoryPicker extends StatelessWidget {
  const IconCategoryPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.searchHint = 'Search emoji',
    this.keyboardHint,
  });

  /// Selected emoji string (stored on topic.icon).
  final String selectedId;
  final ValueChanged<String> onSelected;
  final String searchHint;

  /// Shown under the picker so Tab between grid and sections is discoverable.
  final String? keyboardHint;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.noteBorder.withValues(alpha: 0.85),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: EmojiPicker(
              onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
              customWidget: (config, state, showSearchBar) {
                return _KeyboardEmojiPickerView(
                  config,
                  state,
                  showSearchBar,
                  key: const ValueKey('keyboard-emoji-view'),
                );
              },
              config: Config(
                height: 280,
                checkPlatformCompatibility: !isApple,
                viewOrderConfig: const ViewOrderConfig(
                  top: EmojiPickerItem.searchBar,
                  middle: EmojiPickerItem.emojiView,
                  bottom: EmojiPickerItem.categoryBar,
                ),
                emojiViewConfig: EmojiViewConfig(
                  columns: 8,
                  emojiSizeMax: isApple ? 28 * 1.15 : 28,
                  backgroundColor: AppColors.noteTop,
                  buttonMode: ButtonMode.MATERIAL,
                  gridPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
                skinToneConfig: const SkinToneConfig(enabled: true),
                categoryViewConfig: CategoryViewConfig(
                  initCategory: Category.SMILEYS,
                  recentTabBehavior: RecentTabBehavior.RECENT,
                  backgroundColor: AppColors.noteTop,
                  dividerColor: AppColors.noteBorder,
                  indicatorColor: primary,
                  iconColor: AppColors.textHint,
                  iconColorSelected: AppColors.text,
                  categoryIcons: CategoryIcons(
                    recentIcon: AppIcons.recent,
                    smileyIcon: AppIcons.smiley,
                    animalIcon: AppIcons.animal,
                    foodIcon: AppIcons.food,
                    activityIcon: AppIcons.activity,
                    travelIcon: AppIcons.travel,
                    objectIcon: AppIcons.object,
                    symbolIcon: AppIcons.symbol,
                    flagIcon: AppIcons.flag,
                  ),
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: AppColors.noteTop,
                  buttonColor: AppColors.noteTop,
                  buttonIconColor: AppColors.textHint,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: AppColors.noteTop,
                  buttonIconColor: AppColors.textHint,
                  hintText: searchHint,
                ),
              ),
            ),
          ),
        ),
        if (keyboardHint != null) ...[
          const SizedBox(height: 6),
          DialogKeyboardHint(keyboardHint!),
        ],
      ],
    );
  }
}

class _KeyboardEmojiPickerView extends EmojiPickerView {
  const _KeyboardEmojiPickerView(
    super.config,
    super.state,
    super.showSearchBar, {
    super.key,
  });

  @override
  State<_KeyboardEmojiPickerView> createState() =>
      _KeyboardEmojiPickerViewState();
}

class _KeyboardEmojiPickerViewState extends State<_KeyboardEmojiPickerView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  final _scrollController = ScrollController();
  final _emojisFocus = FocusNode(debugLabel: 'emoji-grid');
  final _sectionsFocus = FocusNode(debugLabel: 'emoji-sections');
  var _emojiIndex = 0;
  double _emojiBoxSize = 32;

  @override
  void initState() {
    super.initState();
    final targetCategory = widget.state.currentCategory ??
        widget.config.categoryViewConfig.initCategory;
    var initCategory = widget.state.categoryEmoji
        .indexWhere((element) => element.category == targetCategory);
    if (initCategory == -1) {
      initCategory = 0;
    }
    _tabController = TabController(
      initialIndex: initCategory,
      length: widget.state.categoryEmoji.length,
      vsync: this,
    );
    _pageController = PageController(initialPage: initCategory);
    widget.state.categoryNavigationNotifier
        .addListener(_onCategoryNavigationChanged);
    _emojisFocus.addListener(_onFocusChanged);
    _sectionsFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onCategoryNavigationChanged() {
    final targetCategory = widget.state.categoryNavigationNotifier.value;
    if (targetCategory == null) return;
    final index = widget.state.categoryEmoji
        .indexWhere((element) => element.category == targetCategory);
    if (index != -1 && index != _pageController.page?.round()) {
      _pageController.jumpToPage(index);
    }
  }

  @override
  void dispose() {
    widget.state.categoryNavigationNotifier
        .removeListener(_onCategoryNavigationChanged);
    _emojisFocus.removeListener(_onFocusChanged);
    _sectionsFocus.removeListener(_onFocusChanged);
    _emojisFocus.dispose();
    _sectionsFocus.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Emoji> get _currentEmojis {
    final i = _tabController.index;
    if (i < 0 || i >= widget.state.categoryEmoji.length) return const [];
    return widget.state.categoryEmoji[i].emoji;
  }

  int get _columns => widget.config.emojiViewConfig.columns;

  void _setCategory(int index) {
    if (index < 0 || index >= widget.state.categoryEmoji.length) return;
    _tabController.animateTo(index);
    _pageController.jumpToPage(index);
    setState(() => _emojiIndex = 0);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _setEmojiIndex(int index) {
    final count = _currentEmojis.length;
    if (count == 0) return;
    final next = index.clamp(0, count - 1);
    setState(() => _emojiIndex = next);
    _ensureEmojiVisible();
  }

  void _ensureEmojiVisible() {
    if (!_scrollController.hasClients) return;
    final row = _emojiIndex ~/ _columns;
    final target = row * _emojiBoxSize;
    final pos = _scrollController.position;
    if (target < pos.pixels ||
        target + _emojiBoxSize > pos.pixels + pos.viewportDimension) {
      _scrollController.jumpTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
    }
  }

  void _selectHighlighted() {
    final emojis = _currentEmojis;
    if (emojis.isEmpty) return;
    final page = _tabController.index;
    final i = _emojiIndex.clamp(0, emojis.length - 1);
    widget.state.onEmojiSelected(
      widget.state.categoryEmoji[page].category,
      emojis[i],
    );
  }

  bool _isActivate(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
  }

  KeyEventResult _onEmojisKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final emojis = _currentEmojis;
    final columns = _columns;
    final count = emojis.length;

    if (_isActivate(key)) {
      _selectHighlighted();
      return KeyEventResult.handled;
    }
    if (count == 0) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _sectionsFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final lastRowStart = (count - 1) ~/ columns * columns;
    if (key == LogicalKeyboardKey.arrowRight) {
      _setEmojiIndex(_emojiIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _setEmojiIndex(_emojiIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_emojiIndex >= lastRowStart) {
        _sectionsFocus.requestFocus();
      } else {
        _setEmojiIndex(_emojiIndex + columns);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _setEmojiIndex(_emojiIndex - columns);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSectionsKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final n = widget.state.categoryEmoji.length;
    if (n == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowRight) {
      _setCategory((_tabController.index + 1) % n);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _setCategory((_tabController.index - 1 + n) % n);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || _isActivate(key)) {
      _emojisFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);
        _emojiBoxSize =
            widget.config.emojiViewConfig.getEmojiBoxSize(constraints.maxWidth);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: EmojiContainer(
            color: widget.config.emojiViewConfig.backgroundColor,
            buttonMode: widget.config.emojiViewConfig.buttonMode,
            child: Column(
              children: [
                ExcludeFocus(child: _buildSearchBar()),
                Flexible(child: _buildEmojiPane(emojiSize, _emojiBoxSize)),
                _buildCategoryPane(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    if (!widget.config.bottomActionBarConfig.enabled) {
      return const SizedBox.shrink();
    }
    return widget.config.bottomActionBarConfig.customBottomActionBar != null
        ? widget.config.bottomActionBarConfig.customBottomActionBar!(
            widget.config,
            widget.state,
            widget.showSearchBar,
          )
        : DefaultBottomActionBar(
            widget.config,
            widget.state,
            widget.showSearchBar,
          );
  }

  Widget _buildEmojiPane(double emojiSize, double emojiBoxSize) {
    return Focus(
      focusNode: _emojisFocus,
      autofocus: true,
      onKeyEvent: _onEmojisKey,
      child: ExcludeFocus(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.fromLTRB(2, 2, 2, 0),
          decoration: DialogFieldStyle.paneFocusDecoration(
            focused: _emojisFocus.hasFocus,
          ),
          child: PageView.builder(
            itemCount: widget.state.categoryEmoji.length,
            controller: _pageController,
            onPageChanged: (index) {
              _tabController.animateTo(
                index,
                duration:
                    widget.config.categoryViewConfig.tabIndicatorAnimDuration,
              );
              setState(() => _emojiIndex = 0);
              if (index < widget.state.categoryEmoji.length) {
                widget.state.onCategoryChanged?.call(
                  widget.state.categoryEmoji[index].category,
                );
              }
            },
            itemBuilder: (context, index) => _buildPage(
              emojiSize,
              emojiBoxSize,
              widget.state.categoryEmoji[index],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPane() {
    return Focus(
      focusNode: _sectionsFocus,
      onKeyEvent: _onSectionsKey,
      child: ExcludeFocus(
        child: Listener(
          onPointerDown: (_) => _sectionsFocus.requestFocus(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
            decoration: DialogFieldStyle.paneFocusDecoration(
              focused: _sectionsFocus.hasFocus,
            ),
            child: _WhatsAppCategoryView(
              widget.config,
              widget.state,
              _tabController,
              _pageController,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    double emojiSize,
    double emojiBoxSize,
    CategoryEmoji categoryEmoji,
  ) {
    if (categoryEmoji.category == Category.RECENT &&
        categoryEmoji.emoji.isEmpty) {
      return Center(child: widget.config.emojiViewConfig.noRecents);
    }
    return GridView.builder(
      key: const Key('emojiScrollView'),
      scrollDirection: Axis.vertical,
      controller: _scrollController,
      primary: false,
      padding: widget.config.emojiViewConfig.gridPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        childAspectRatio: 1,
        crossAxisCount: widget.config.emojiViewConfig.columns,
        mainAxisSpacing: widget.config.emojiViewConfig.verticalSpacing,
        crossAxisSpacing: widget.config.emojiViewConfig.horizontalSpacing,
      ),
      itemCount: categoryEmoji.emoji.length,
      itemBuilder: (context, index) {
        final highlighted = _emojisFocus.hasFocus && index == _emojiIndex;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: highlighted
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.54),
                    width: 0.9,
                  )
                : null,
          ),
          child: EmojiCell.fromConfig(
            emoji: categoryEmoji.emoji[index],
            emojiSize: emojiSize,
            emojiBoxSize: emojiBoxSize,
            categoryEmoji: categoryEmoji,
            onEmojiSelected: widget.state.onEmojiSelected,
            config: widget.config,
          ),
        );
      },
    );
  }
}

class _WhatsAppCategoryView extends CategoryView {
  const _WhatsAppCategoryView(
    super.config,
    super.state,
    super.tabController,
    super.pageController,
  );

  @override
  _WhatsAppCategoryViewState createState() => _WhatsAppCategoryViewState();
}

class _WhatsAppCategoryViewState extends State<_WhatsAppCategoryView>
    with SkinToneOverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.config.categoryViewConfig.backgroundColor,
      child: TabBar(
        labelColor: widget.config.categoryViewConfig.iconColorSelected,
        unselectedLabelColor: widget.config.categoryViewConfig.iconColor,
        dividerColor: widget.config.categoryViewConfig.dividerColor,
        controller: widget.tabController,
        labelPadding: const EdgeInsets.only(top: 1),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x1F000000),
        ),
        onTap: (index) {
          closeSkinToneOverlay();
          widget.pageController.jumpToPage(index);
        },
        tabs: widget.state.categoryEmoji
            .map(
              (item) => Tab(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    getIconForCategory(
                      widget.config.categoryViewConfig.categoryIcons,
                      item.category,
                    ),
                    size: 20,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
