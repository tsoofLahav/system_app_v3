import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../shell/app_bottom_bar.dart';
import '../widgets/topic_emoji.dart';

/// The strip at the top of a topic: which topic this is, and the one button
/// that belongs to the topic itself.
///
/// It floats above the files rather than scrolling with them. The topic colour
/// wash itself is painted by [AppShellCanvas] across the whole window (including
/// behind the sidebar); this header only carries the name and the `+`.
class TopicHeader extends StatelessWidget {
  const TopicHeader({
    super.key,
    required this.topic,
    required this.accent,
    required this.state,
    required this.onAddFile,
    this.addEnabled = true,
  });

  final Topic topic;
  final Color accent;
  final AppState state;
  final VoidCallback onAddFile;
  final bool addEnabled;

  @override
  Widget build(BuildContext context) {
    final isMain = topic.isMain;
    final s = state.strings;

    return SizedBox(
      height: AppTopicHeaderMetrics.scrollTopInset,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTopicHeaderMetrics.horizontalMargin,
          AppTopicHeaderMetrics.floatMargin,
          AppTopicHeaderMetrics.horizontalMargin,
          0,
        ),
        child: SizedBox(
          height: AppTopicHeaderMetrics.headerHeight,
          child: Row(
            children: [
              if (!isMain) ...[
                TopicEmoji(value: topic.icon, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  state.topicDisplayName(topic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.noteTitleStyle.copyWith(
                    fontSize: 15,
                    height: 1.2,
                    color: AppColors.text.withValues(alpha: 0.94),
                  ),
                ),
              ),
              const SizedBox(width: AppTopicHeaderMetrics.headerGap),
              Opacity(
                opacity: addEnabled ? 1 : 0.35,
                child: GlassCircleButton(
                  tooltip: s['addFile'],
                  icon: AppIcons.add,
                  onPressed: addEnabled ? onAddFile : () {},
                  size: AppTopicHeaderMetrics.addButtonSize,
                  iconSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
