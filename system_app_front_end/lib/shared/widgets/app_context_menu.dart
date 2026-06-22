import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';

/// One row or divider in a compact context menu.
sealed class AppContextMenuEntry {
  const AppContextMenuEntry();
}

class AppContextMenuItem extends AppContextMenuEntry {
  const AppContextMenuItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.destructive = false,
  });

  final String value;
  final String label;
  final bool enabled;
  final bool destructive;
}

class AppContextMenuDivider extends AppContextMenuEntry {
  const AppContextMenuDivider();
}

abstract final class AppContextMenu {
  static const _itemHeight = 30.0;
  static const _horizontalPadding = 12.0;

  static TextStyle _labelStyle({bool destructive = false}) =>
      AppTypography.metaStyle.copyWith(
        fontSize: 11,
        height: 1.2,
        color: destructive
            ? const Color(0xFFB45309)
            : AppColors.text.withValues(alpha: 0.9),
      );

  static Future<String?> show({
    required BuildContext context,
    required Offset globalPosition,
    required List<AppContextMenuEntry> entries,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        for (final entry in entries) _toPopupEntry(entry),
      ],
    );
  }

  static PopupMenuEntry<String> _toPopupEntry(AppContextMenuEntry entry) {
    if (entry is AppContextMenuDivider) {
      return const PopupMenuDivider(height: 9);
    }
    final item = entry as AppContextMenuItem;
    return PopupMenuItem<String>(
      value: item.value,
      enabled: item.enabled,
      height: _itemHeight,
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Text(
        item.label,
        style: _labelStyle(destructive: item.destructive),
      ),
    );
  }
}
