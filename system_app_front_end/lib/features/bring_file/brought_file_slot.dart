import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/brought_file_snapshot.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/widgets/file_section.dart';

class BroughtFileSlot extends StatelessWidget {
  const BroughtFileSlot({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final guest = state.broughtFile;
    if (guest == null) return const SizedBox.shrink();

    final s = state.strings;
    final accent = TopicAppearance.colorFromHex(guest.sourceTopic.color);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        FileSection(
          topic: guest.sourceTopic,
          file: guest.file,
          blocks: guest.blocks,
          state: state,
          accent: accent,
          tasksByBlockId: guest.tasksByBlockId,
          isGuestFile: true,
          onDelete: () {},
        ),
        Positioned.directional(
          textDirection: state.textDirection,
          top: 10,
          end: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(
                borderRadius: BorderRadius.circular(999),
                tintColor: accent,
                tintOpacity: 0.18,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  s.bringFileFromTopicNamed(
                    state.topicDisplayName(guest.sourceTopic),
                  ),
                  style: AppTypography.metaStyle.copyWith(
                    color: accent.withValues(alpha: 0.92),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GlassCircleButton(
                tooltip: s['bringFileDismiss'],
                icon: AppIcons.close,
                onPressed: state.clearBroughtFile,
                size: 28,
                iconSize: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Builds the guest file slot when [snapshot] is non-null.
Widget? broughtFileLayoutSlot({
  required AppState state,
  required BroughtFileSnapshot? snapshot,
}) {
  if (snapshot == null) return null;
  return BroughtFileSlot(state: state);
}
