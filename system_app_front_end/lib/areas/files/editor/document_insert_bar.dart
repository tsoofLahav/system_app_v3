import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_icons.dart';
import '../../ui/glass_surface.dart';
import './document_editor_controller.dart';
import '../../ux/shell/app_bottom_bar.dart';

class DocumentInsertBar extends StatelessWidget {
  const DocumentInsertBar({
    super.key,
    required this.state,
    this.embedded = false,
  });

  final AppState state;

  /// When true, the bar sits beside the bottom tools on the same baseline —
  /// no SafeArea, no centering of its own.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DocumentEditorRegistry.notifier,
      builder: (context, _) {
        final controller = DocumentEditorRegistry.active;
        if (controller == null) return const SizedBox.shrink();

        final s = state.strings;
        final segment = GlassBarSegment(
          height: AppBottomBarMetrics.barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InsertButton(
                icon: AppIcons.uploadDetails,
                tooltip: s['paragraph'],
                onPressed: () => controller.insertAtBlock('paragraph'),
              ),
              // One list option only. Points vs numbers is a property of
              // an existing list, switched from its right-click menu.
              _InsertButton(
                icon: AppIcons.smartList,
                tooltip: s['list'],
                onPressed: () => controller.insertAtBlock('bullet_list'),
              ),
              _InsertButton(
                icon: AppIcons.layout,
                tooltip: s['table'],
                onPressed: () => controller.insertAtBlock('table'),
              ),
              _InsertButton(
                icon: AppIcons.check,
                tooltip: s['addTaskList'],
                onPressed: () => controller.insertAtBlock('task_list'),
              ),
              _InsertButton(
                icon: AppIcons.object,
                tooltip: s['addDetails'],
                onPressed: () => controller.insertAtBlock('info'),
              ),
              _InsertButton(
                icon: AppIcons.image,
                tooltip: s['addImage'],
                onPressed: () => controller.insertAtBlock('image'),
              ),
              _InsertButton(
                icon: AppIcons.graph,
                tooltip: s['addGraph'],
                onPressed: () => controller.insertAtBlock('graph'),
              ),
            ],
          ),
        );

        if (embedded) return segment;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 4),
            child: Center(child: segment),
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
    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: onPressed,
      icon: AppIcon(icon, size: 20),
    );
  }
}
