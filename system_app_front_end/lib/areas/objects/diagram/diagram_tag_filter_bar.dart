import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/models/tag.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/topic/topic_appearance.dart';

/// Horizontal tag chips for filtering the objects diagram — sits beside the bottom bar.
class DiagramTagFilterBar extends StatelessWidget {
  const DiagramTagFilterBar({
    super.key,
    required this.state,
    this.tightShadow = false,
  });

  final AppState state;
  final bool tightShadow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final tags = state.objectTags;
        if (tags.isEmpty) {
          return GlassBarSegment(
            height: 44,
            tightShadow: tightShadow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  state.strings['noTagsYet'],
                  style: AppTypography.metaStyle,
                ),
              ),
            ),
          );
        }
        return GlassBarSegment(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tightShadow: tightShadow,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tag in tags) ...[
                  _DiagramTagChip(
                    tag: tag,
                    selected: state.diagramFilterTagIds.contains(tag.id),
                    onTap: () => state.toggleDiagramFilterTag(tag.id),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiagramTagChip extends StatelessWidget {
  const _DiagramTagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final AppTag tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = TopicAppearance.colorFromHex(
      tag.color ?? TopicAppearance.defaultColor,
    );
    return Material(
      color: selected ? color.withValues(alpha: 0.28) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tag.icon?.isNotEmpty == true
                    ? tag.icon!
                    : TopicAppearance.defaultEmoji,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(tag.name, style: AppTypography.metaStyle),
            ],
          ),
        ),
      ),
    );
  }
}
