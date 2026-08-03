import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/glass_surface.dart';
import '../../ux/shell/app_bottom_bar.dart';

/// Compact floating chrome for the view page — same capsule language as the
/// bottom bar.
class ViewChromeMenu extends StatelessWidget {
  const ViewChromeMenu({
    super.key,
    required this.state,
    required this.displayMode,
    required this.frameReorderMode,
    required this.onDisplayMode,
    required this.onAddSection,
    required this.onToggleFrameReorder,
  });

  final AppState state;
  final ViewDisplayMode displayMode;
  final bool frameReorderMode;
  final ValueChanged<ViewDisplayMode> onDisplayMode;
  final VoidCallback onAddSection;
  final VoidCallback onToggleFrameReorder;

  static const _segmentPadding = EdgeInsets.symmetric(horizontal: 4);
  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final bySection = displayMode != ViewDisplayMode.byTopic;

    return GlassBarSegment(
      height: AppBottomBarMetrics.barHeight,
      padding: _segmentPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChromeIconButton(
            tooltip: s['bySection'],
            icon: AppIcons.layout,
            active: bySection,
            onPressed: () => onDisplayMode(ViewDisplayMode.bySection),
          ),
          _ChromeIconButton(
            tooltip: s['byTopic'],
            icon: AppIcons.smartList,
            active: !bySection,
            onPressed: () => onDisplayMode(ViewDisplayMode.byTopic),
          ),
          if (bySection)
            _ChromeIconButton(
              tooltip: s['addSection'],
              icon: AppIcons.add,
              onPressed: onAddSection,
            ),
          _ChromeIconButton(
            tooltip: bySection ? s['reorderSections'] : s['reorderTopics'],
            icon: AppIcons.arrange,
            active: frameReorderMode,
            onPressed: onToggleFrameReorder,
          ),
        ],
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.primaryBright.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AppIcon(
              icon,
              size: ViewChromeMenu._iconSize,
              color: active
                  ? AppColors.primary.withValues(alpha: 0.95)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
