import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';

/// WhatsApp-style emoji picker (standard categories + full emoji set).
class IconCategoryPicker extends StatelessWidget {
  const IconCategoryPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.searchHint = 'Search emoji',
  });

  /// Selected emoji string (stored on topic.icon).
  final String selectedId;
  final ValueChanged<String> onSelected;
  final String searchHint;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: EmojiPicker(
          onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
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
              gridPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
              customCategoryView: (config, state, tabController, pageController) {
                return _WhatsAppCategoryView(
                  config,
                  state,
                  tabController,
                  pageController,
                );
              },
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
