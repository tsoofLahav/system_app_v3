import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/glass_surface.dart';
import '../document/document_editor_controller.dart';
import '../shell/app_bottom_bar.dart';

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
                      tooltip: 'Paragraph',
                      onPressed: () => controller.insertAtBlock('paragraph'),
                    ),
                    _InsertButton(
                      icon: AppIcons.smartList,
                      tooltip: 'Bullet list',
                      onPressed: () => controller.insertAtBlock('bullet_list'),
                    ),
                    _InsertButton(
                      icon: LucideIcons.list200,
                      tooltip: 'Numbered list',
                      onPressed: () => controller.insertAtBlock('ordered_list'),
                    ),
                    _InsertButton(
                      icon: AppIcons.layout,
                      tooltip: 'Table',
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
