import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/glass_surface.dart';

/// Phone bottom bar talks to the open view pane through this.
class ViewChromeHost {
  const ViewChromeHost({
    required this.onToggleDisplayMode,
    required this.onAddSection,
    required this.onStartFrameReorder,
    required this.onToggleTaskReorder,
    required this.frameReorderMode,
  });

  final VoidCallback onToggleDisplayMode;
  final VoidCallback onAddSection;
  final VoidCallback onStartFrameReorder;
  final VoidCallback onToggleTaskReorder;
  final bool frameReorderMode;
}

class ViewChromeRegistry extends ChangeNotifier {
  ViewChromeRegistry._();
  static final instance = ViewChromeRegistry._();
  static ChangeNotifier get notifier => instance;
  static ViewChromeHost? active;

  static void attach(ViewChromeHost host) {
    active = host;
    instance.notifyListeners();
  }

  static void detach(ViewChromeHost host) {
    if (active != host) return;
    active = null;
    instance.notifyListeners();
  }
}

/// Compact floating chrome for the view page — same capsule language as the
/// bottom bar. On phone it sits in [PhoneBottomBar], not as a second overlay.
class ViewChromeMenu extends StatelessWidget {
  const ViewChromeMenu({
    super.key,
    required this.state,
    required this.displayMode,
    required this.frameReorderMode,
    required this.onToggleDisplayMode,
    required this.onAddSection,
    required this.onStartFrameReorder,
  });

  final AppState state;
  final ViewDisplayMode displayMode;
  final bool frameReorderMode;
  final VoidCallback onToggleDisplayMode;
  final VoidCallback onAddSection;
  /// Enters frame-reorder mode; exit is tap-outside-frames on the view pane.
  final VoidCallback onStartFrameReorder;

  static const _segmentPadding = EdgeInsets.symmetric(horizontal: 4);
  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final bySection = displayMode != ViewDisplayMode.byTopic;

    return GlassBarSegment(
      height: isPhoneLayout ? 38 : 44,
      padding: _segmentPadding,
      tightShadow: isPhoneLayout,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChromeIconButton(
            tooltip: bySection ? s['switchToTopics'] : s['switchToSections'],
            icon: AppIcons.swap,
            onPressed: onToggleDisplayMode,
          ),
          _ChromeIconButton(
            tooltip: s['addSection'],
            icon: AppIcons.add,
            enabled: bySection,
            onPressed: bySection ? onAddSection : null,
          ),
          _ChromeIconButton(
            tooltip: bySection ? s['reorderSections'] : s['reorderTopics'],
            icon: AppIcons.arrange,
            active: frameReorderMode,
            onPressed: frameReorderMode ? null : onStartFrameReorder,
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
    this.onPressed,
    this.active = false,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active && enabled
            ? AppColors.primaryBright.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AppIcon(
              icon,
              size: ViewChromeMenu._iconSize,
              enabled: enabled,
              color: !enabled
                  ? null
                  : active
                      ? AppColors.primary.withValues(alpha: 0.95)
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}
