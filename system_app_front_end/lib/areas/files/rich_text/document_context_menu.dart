import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_colors.dart';
import '../../ui/color_dialog.dart';
import '../../ux/widgets/app_context_menu.dart';
import './block_text_focus.dart';

typedef DocumentMenuHandler = Future<void> Function(String action);

class DocumentContextMenu {
  const DocumentContextMenu._();

  static List<AppContextMenuEntry> buildTextEntries(
    AppStrings strings, {
    bool includeConnectInfo = false,
  }) => [
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
    AppContextMenuItem(
      value: 'text:color:pick',
      label: strings['chooseColor'] ?? 'Choose color',
    ),
    AppContextMenuItem(
      value: 'text:color:clear',
      label: strings['clearColor'] ?? 'Clear color',
    ),
    if (includeConnectInfo) ...[
      const AppContextMenuDivider(),
      AppContextMenuItem(
        value: 'text:connect_info',
        label: strings['connectInfo'] ?? 'Connect info…',
      ),
    ],
    const AppContextMenuDivider(),
    AppContextMenuItem(value: 'text:cut', label: strings['cut'] ?? 'Cut'),
    AppContextMenuItem(value: 'text:copy', label: strings['copy'] ?? 'Copy'),
    AppContextMenuItem(value: 'text:paste', label: strings['paste'] ?? 'Paste'),
  ];

  static Future<void> _showMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    required List<AppContextMenuEntry> entries,
  }) async {
    AppContextMenu.dismissActive();
    BlockTextFocusRegistry.openMenuSession();
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
      isRtl: strings.isRtl,
    );
    // Keep the mark frozen while the colour dialog is open.
    if (value == 'text:color:pick' && context.mounted) {
      final hex = await showAppColorDialog(
        context: context,
        strings: strings,
        selectedHex: AppColors.colorToHex(AppColors.text),
      );
      if (hex != null && context.mounted) {
        await onAction('text:color:$hex');
      }
    } else if (value != null) {
      await onAction(value);
    }
    BlockTextFocusRegistry.closeMenuSession();
  }

  static Future<void> showTextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    bool includeConnectInfo = false,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: buildTextEntries(
        strings,
        includeConnectInfo: includeConnectInfo,
      ),
    );
  }

  /// List menu: the text actions plus the one control that decides whether the
  /// list shows points or numbers.
  ///
  /// A list has a single style, so this is a switch on the existing block
  /// rather than two kinds of list to insert.
  static Future<void> showListMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required bool isOrdered,
    required DocumentMenuHandler onAction,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        ...buildTextEntries(strings, includeConnectInfo: true),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: isOrdered ? 'list:style:bullet' : 'list:style:numbered',
          label: isOrdered
              ? strings['switchToPoints']
              : strings['switchToNumbers'],
        ),
      ],
    );
  }

  static Future<void> showTableCellMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        ...buildTextEntries(strings, includeConnectInfo: true),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'table:add_column',
          label: strings['addColumn'] ?? 'Add column',
        ),
      ],
    );
  }

  /// Info embed menu: text actions + Add tag / Add connection.
  static Future<void> showInfoMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        ...buildTextEntries(strings),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'info:add_tag',
          label: strings['addTag'],
        ),
        AppContextMenuItem(
          value: 'info:add_connection',
          label: strings['addConnection'],
        ),
      ],
    );
  }

  /// Task list menu: text actions, assign to views, Reorder Mode.
  static Future<void> showTaskListMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    List<AppContextMenuEntry> extraEntries = const [],
    bool includeAssignView = true,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        ...buildTextEntries(strings),
        const AppContextMenuDivider(),
        if (includeAssignView)
          AppContextMenuItem(
            value: 'tasks:assign_view',
            label: strings['assignTaskViews'],
          ),
        AppContextMenuItem(
          value: 'tasks:reorder_mode',
          label: strings['reorderTasks'],
        ),
        ...extraEntries,
      ],
    );
  }
}
