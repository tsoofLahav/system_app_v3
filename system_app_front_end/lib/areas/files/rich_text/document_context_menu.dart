import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ux/widgets/app_context_menu.dart';
import './block_text_focus.dart';

typedef DocumentMenuHandler = Future<void> Function(String action);

class DocumentContextMenu {
  const DocumentContextMenu._();

  static List<AppContextMenuEntry> buildTextEntries(AppStrings strings) => [
    AppContextMenuItem(value: 'text:bold', label: strings['bold'] ?? 'Bold'),
    AppContextMenuItem(value: 'text:italic', label: strings['italic'] ?? 'Italic'),
    AppContextMenuItem(
      value: 'text:underline',
      label: strings['underline'] ?? 'Underline',
    ),
    AppContextMenuItem(
      value: 'text:size_up',
      label: strings['sizeUp'] ?? 'Size up',
    ),
    AppContextMenuItem(
      value: 'text:size_down',
      label: strings['sizeDown'] ?? 'Size down',
    ),
    const AppContextMenuDivider(),
    AppContextMenuItem(value: 'text:color:#E53935', label: 'Red'),
    AppContextMenuItem(value: 'text:color:#1E88E5', label: 'Blue'),
    AppContextMenuItem(value: 'text:color:#43A047', label: 'Green'),
    AppContextMenuItem(value: 'text:color:#FB8C00', label: 'Orange'),
    AppContextMenuItem(value: 'text:color:clear', label: 'Clear color'),
    const AppContextMenuDivider(),
    AppContextMenuItem(value: 'text:cut', label: strings['cut'] ?? 'Cut'),
    AppContextMenuItem(value: 'text:copy', label: strings['copy'] ?? 'Copy'),
    AppContextMenuItem(value: 'text:paste', label: strings['paste'] ?? 'Paste'),
  ];

  static Future<void> showTextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
  }) async {
    AppContextMenu.dismissActive();
    BlockTextFocusRegistry.openMenuSession();
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      entries: buildTextEntries(strings),
      isRtl: strings.isRtl,
    );
    if (value != null) {
      await onAction(value);
    }
    BlockTextFocusRegistry.closeMenuSession();
  }

  static Future<void> showTableCellMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
  }) async {
    AppContextMenu.dismissActive();
    BlockTextFocusRegistry.openMenuSession();
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      entries: [
        ...buildTextEntries(strings),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'table:add_column',
          label: strings['addColumn'] ?? 'Add column',
        ),
      ],
      isRtl: strings.isRtl,
    );
    if (value != null) {
      await onAction(value);
    }
    BlockTextFocusRegistry.closeMenuSession();
  }
}
