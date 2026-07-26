import 'package:flutter/material.dart';

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
                      tooltip: 'Paragraph break',
                      onPressed: () => controller.insertAtCaret('paragraph'),
                    ),
                    _InsertButton(
                      icon: AppIcons.smartList,
                      tooltip: 'List',
                      onPressed: () => controller.insertAtCaret('list'),
                    ),
                    _InsertButton(
                      icon: AppIcons.layout,
                      tooltip: 'Table',
                      onPressed: () => controller.insertAtCaret('table'),
                    ),
                    _InsertButton(
                      icon: AppIcons.image,
                      tooltip: 'Image',
                      onPressed: () => controller.insertAtCaret('image'),
                    ),
                    _InsertButton(
                      icon: AppIcons.graph,
                      tooltip: 'Graph',
                      onPressed: () => controller.insertAtCaret('graph'),
                    ),
                    _InsertButton(
                      icon: AppIcons.check,
                      tooltip: state.strings['addTask'] ?? 'Task list',
                      onPressed: () => controller.insertAtCaret('task_list'),
                    ),
                    _InsertButton(
                      icon: AppIcons.consult,
                      tooltip: 'Info',
                      onPressed: () => controller.insertAtCaret('info'),
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
