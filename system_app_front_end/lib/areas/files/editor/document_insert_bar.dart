import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/glass_surface.dart';
import '../rich_text/text_emoji_picker.dart';
import './document_editor_controller.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/shortcuts/app_shortcuts.dart';
import '../../ux/shortcuts/shortcut_catalog.dart';

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
      listenable: Listenable.merge([
        DocumentEditorRegistry.notifier,
        TextEmojiPalette.open,
      ]),
      builder: (context, _) {
        final controller = DocumentEditorRegistry.active;
        if (controller == null) return const SizedBox.shrink();

        final s = state.strings;
        final segment = GlassBarSegment(
          height: AppBottomBarMetrics.segmentHeight(phone: isPhoneLayout),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tightShadow: isPhoneLayout,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No paragraph button — a file is free text, so a plain line is
              // always one keystroke away. The bar is for what typing cannot
              // make: emoji, a list, and the objects.
              _InsertButton(
                icon: AppIcons.smiley,
                tooltip: _tooltip(
                  state,
                  s['insertEmoji'],
                  ShortcutActionIds.insertEmoji,
                ),
                selected: TextEmojiPalette.isOpen,
                onPressed: () => TextEmojiPalette.toggle(context, s),
              ),
              // One list option only. Points vs numbers is a property of
              // an existing list, switched from its right-click menu.
              _InsertButton(
                icon: AppIcons.smartList,
                tooltip: _tooltip(
                  state,
                  s['list'],
                  ShortcutActionIds.addConnection,
                ),
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

  static String _tooltip(AppState state, String label, String actionId) {
    final suffix = shortcutTooltipSuffix(state, actionId);
    if (suffix == null) return label;
    return '$label ($suffix)';
  }
}

/// Smiley on the bottom bar when there is no full insert strip — views.
class ViewEmojiInsertBar extends StatelessWidget {
  const ViewEmojiInsertBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TextEmojiPalette.open,
      builder: (context, _) {
        final s = state.strings;
        return GlassBarSegment(
          height: AppBottomBarMetrics.segmentHeight(phone: isPhoneLayout),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tightShadow: isPhoneLayout,
          child: _InsertButton(
            icon: AppIcons.smiley,
            tooltip: DocumentInsertBar._tooltip(
              state,
              s['insertEmoji'],
              ShortcutActionIds.insertEmoji,
            ),
            selected: TextEmojiPalette.isOpen,
            onPressed: () => TextEmojiPalette.toggle(context, s),
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
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      child: IconButton(
        tooltip: tooltip,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: onPressed,
        icon: AppIcon(
          icon,
          size: 20,
          color: selected ? AppColors.primary : null,
        ),
      ),
    );
  }
}
