import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_icons.dart';
import '../../ui/glass_surface.dart';
import './document_editor_controller.dart';
import '../../ux/shell/app_bottom_bar.dart';

class DocumentInsertBar extends StatelessWidget {
  const DocumentInsertBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DocumentEditorRegistry.notifier,
      builder: (context, _) {
        final controller = DocumentEditorRegistry.active;
        if (controller == null) return const SizedBox.shrink();

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 4,
            ),
            child: Center(
              child: GlassBarSegment(
                height: AppBottomBarMetrics.barHeight,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InsertButton(
                      icon: AppIcons.uploadDetails,
                      tooltip: state.strings['paragraph'],
                      onPressed: () => controller.insertAtBlock('paragraph'),
                    ),
                    // One list option only. Points vs numbers is a property of
                    // an existing list, switched from its right-click menu.
                    _InsertButton(
                      icon: AppIcons.smartList,
                      tooltip: state.strings['list'],
                      onPressed: () => controller.insertAtBlock('bullet_list'),
                    ),
                    _InsertButton(
                      icon: AppIcons.layout,
                      tooltip: state.strings['table'],
                      onPressed: () => controller.insertAtBlock('table'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InsertButton extends StatelessWidget {
  const _InsertButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: AppIcon(icon, size: 20),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
