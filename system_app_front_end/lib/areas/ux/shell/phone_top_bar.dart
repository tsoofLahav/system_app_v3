import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import './app_bottom_bar.dart';
import './dismiss_focus_on_outside_tap.dart';
import './phone_visible_file.dart';
import '../../files/data/topic.dart';
import '../widgets/topic_emoji.dart';

/// Floating phone header: icon pills + bold topic/file names on the ombre.
class PhoneTopBar extends StatelessWidget {
  const PhoneTopBar({
    super.key,
    required this.state,
    required this.title,
    required this.onOpenMenu,
    required this.showAddFile,
    required this.showBringFile,
    required this.onAddFile,
    required this.onBringFile,
  });

  final AppState state;
  final String title;
  final VoidCallback onOpenMenu;
  final bool showAddFile;
  final bool showBringFile;
  final VoidCallback onAddFile;
  final VoidCallback onBringFile;

  static final _nameStyle = AppTypography.noteTitleStyle.copyWith(
    fontSize: 13,
    height: AppTypography.phoneHeaderLineHeight,
    fontWeight: FontWeight.w700,
    color: AppColors.text.withValues(alpha: 0.96),
  );

  @override
  Widget build(BuildContext context) {
    return KeepEditorFocus(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          PhoneVisibleFile.name,
          PhoneVisibleFile.source,
        ]),
        builder: (context, _) {
          final fileName = PhoneVisibleFile.name.value;
          final hasFile = fileName != null && fileName.isNotEmpty;
          final currentTopic = state.isViewMode || state.isDiagramMode
              ? null
              : state.isArchiveMode
              ? state.selectedArchiveTopic
              : state.selectedTopic;
          final source = hasFile ? PhoneVisibleFile.sourceTopic : null;
          final projected =
              source != null &&
              currentTopic != null &&
              source.id != currentTopic.id;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _TopIconPill(
                  tooltip: state.strings['openMenu'],
                  icon: AppIcons.menu,
                  onPressed: onOpenMenu,
                ),
                Expanded(
                  child: SizedBox(
                    height: AppBottomBarMetrics.phoneSegmentHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (projected)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _topicLabel(title, currentTopic),
                          ),
                        Align(
                          alignment: projected
                              ? Alignment.topCenter
                              : Alignment.center,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: projected
                                  ? 13 * AppTypography.phoneHeaderLineHeight +
                                        AppTypography.phoneHeaderProjectedRowGap
                                  : 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: _topicLabel(
                                    projected
                                        ? state.topicHeadline(source)
                                        : title,
                                    projected ? source : currentTopic,
                                  ),
                                ),
                                if (hasFile) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text('·', style: _nameStyle),
                                  ),
                                  Flexible(
                                    child: Text(
                                      fileName,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _nameStyle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBringFile)
                      _TopIconPill(
                        tooltip: state.strings['bringFile'],
                        icon: AppIcons.bringFile,
                        onPressed: onBringFile,
                      ),
                    if (showBringFile && showAddFile) const SizedBox(width: 6),
                    if (showAddFile)
                      _TopIconPill(
                        tooltip: state.strings['addFile'],
                        icon: AppIcons.add,
                        onPressed: onAddFile,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _topicLabel(String label, Topic? topic) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (topic != null && !topic.isMain) ...[
        Transform.translate(
          offset: const Offset(0, AppTypography.phoneHeaderEmojiLift),
          child: TopicEmoji(value: topic.icon, size: 14),
        ),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _nameStyle,
        ),
      ),
    ],
  );
}

class _TopIconPill extends StatelessWidget {
  const _TopIconPill({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassBarSegment(
      style: AppGlassStyle.phoneFloating,
      height: AppBottomBarMetrics.phoneSegmentHeight,
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(7),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        icon: AppIcon(
          icon,
          size: 22,
          weight: AppIcon.phoneBarWeight,
          color: AppColors.text,
        ),
      ),
    );
  }
}
