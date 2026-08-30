import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_colors.dart';
import '../../ui/color_dialog.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../editor/document_secondary_tap.dart';
import '../editor/embeds/image_display_size.dart';
import './block_text_focus.dart';

typedef DocumentMenuHandler = Future<void> Function(String action);

class DocumentContextMenu {
  const DocumentContextMenu._();

  static List<AppContextMenuEntry> buildTextEntries(
    AppStrings strings, {
    bool includeConnectInfo = false,
    bool includeDisconnectInfo = false,
    bool includeMakeList = false,
  }) => [
    AppContextMenuItem(value: 'text:bold', label: strings['bold'] ?? 'Bold'),
    AppContextMenuItem(
      value: 'text:italic',
      label: strings['italic'] ?? 'Italic',
    ),
    AppContextMenuItem(
      value: 'text:underline',
      label: strings['underline'] ?? 'Underline',
    ),
    AppContextMenuItem(
      value: 'text:strikethrough',
      label: strings['strikethrough'] ?? 'Strikethrough',
    ),
    AppContextMenuItem(
      value: 'text:make_link',
      label: strings['makeLink'] ?? 'Make link',
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
    if (includeConnectInfo || includeDisconnectInfo) ...[
      const AppContextMenuDivider(),
      if (includeConnectInfo)
        AppContextMenuItem(
          value: 'text:connect_info',
          label: strings['connectInfo'] ?? 'Connect info…',
        ),
      if (includeDisconnectInfo)
        AppContextMenuItem(
          value: 'text:disconnect_info',
          label: strings['removeConnection'] ?? 'Remove connection',
        ),
    ],
    const AppContextMenuDivider(),
    AppContextMenuItem(value: 'text:cut', label: strings['cut'] ?? 'Cut'),
    AppContextMenuItem(value: 'text:copy', label: strings['copy'] ?? 'Copy'),
    AppContextMenuItem(value: 'text:paste', label: strings['paste'] ?? 'Paste'),
    if (includeMakeList) ...[
      const AppContextMenuDivider(),
      AppContextMenuItem(
        value: 'list:make',
        label: strings['makeList'] ?? 'Make list',
      ),
    ],
  ];

  /// Design… — opens the sample dialog for look (and graph type / colours).
  static AppContextMenuItem designItem(AppStrings strings) =>
      AppContextMenuItem(value: 'object:design', label: strings['design']);

  /// Image block: nudge a little, or jump to a named fraction of the pane.
  static List<AppContextMenuEntry> buildImageEntries(
    AppStrings strings, {
    double scale = ImageDisplaySize.full,
    bool canMergeNext = false,
  }) => [
    AppContextMenuItem(
      value: 'image:smaller',
      label: strings['imageMakeSmaller'],
    ),
    AppContextMenuItem(
      value: 'image:larger',
      label: strings['imageMakeLarger'],
    ),
    const AppContextMenuDivider(),
    AppContextMenuItem(
      value: 'image:size:tiny',
      label: strings['imageSizeTiny'],
      checked: ImageDisplaySize.matchesNamed(scale, ImageDisplaySize.tiny),
    ),
    AppContextMenuItem(
      value: 'image:size:quarter',
      label: strings['imageSizeQuarter'],
      checked: ImageDisplaySize.matchesNamed(scale, ImageDisplaySize.quarter),
    ),
    AppContextMenuItem(
      value: 'image:size:half',
      label: strings['imageSizeHalf'],
      checked: ImageDisplaySize.matchesNamed(scale, ImageDisplaySize.half),
    ),
    AppContextMenuItem(
      value: 'image:size:full',
      label: strings['imageSizeFull'],
      checked: ImageDisplaySize.matchesNamed(scale, ImageDisplaySize.full),
    ),
    if (canMergeNext) ...[
      const AppContextMenuDivider(),
      AppContextMenuItem(
        value: 'image:merge_next',
        label: strings['mergeWithNext'],
      ),
    ],
  ];

  static Future<void> showImageMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    double scale = ImageDisplaySize.full,
    bool canMergeNext = false,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        AppContextMenuItem(
          value: 'object:move_mode',
          label: strings['moveObject'],
        ),
        const AppContextMenuDivider(),
        designItem(strings),
        const AppContextMenuDivider(),
        ...buildImageEntries(strings, scale: scale, canMergeNext: canMergeNext),
      ],
    );
  }

  static Future<void> _showMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    required List<AppContextMenuEntry> entries,
  }) async {
    AppContextMenu.dismissActive();
    final session = BlockTextFocusRegistry.openMenuSession();
    try {
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
    } finally {
      BlockTextFocusRegistry.closeMenuSession(session);
      DocumentSecondaryTap.clearEmbedHandled();
    }
  }

  static Future<void> showTextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    bool includeConnectInfo = false,
    bool includeDisconnectInfo = false,
    bool includeMakeList = false,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: buildTextEntries(
        strings,
        includeConnectInfo: includeConnectInfo,
        includeDisconnectInfo: includeDisconnectInfo,
        includeMakeList: includeMakeList,
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
        ...buildTextEntries(strings, includeConnectInfo: false),
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
    List<AppContextMenuEntry> extraEntries = const [],
    bool includeAddRow = true,
    bool includeReorderRows = true,
    bool includeReorderColumns = true,
    bool includeConnectInfo = true,
    bool includeDisconnectInfo = false,
    bool includeMoveObject = false,
    bool includeDesign = true,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        if (includeMoveObject) ...[
          AppContextMenuItem(
            value: 'object:move_mode',
            label: strings['moveObject'],
          ),
          const AppContextMenuDivider(),
        ],
        ...buildTextEntries(
          strings,
          includeConnectInfo: includeConnectInfo,
          includeDisconnectInfo: includeDisconnectInfo,
        ),
        const AppContextMenuDivider(),
        if (includeAddRow)
          AppContextMenuItem(
            value: 'table:add_row',
            label: strings['addRowAfter'],
          ),
        AppContextMenuItem(
          value: 'table:add_column',
          label: strings['addColumnAfter'],
        ),
        if (includeReorderRows)
          AppContextMenuItem(
            value: 'table:reorder_rows',
            label: strings['reorderRows'],
          ),
        if (includeReorderColumns)
          AppContextMenuItem(
            value: 'table:reorder_columns',
            label: strings['reorderColumns'],
          ),
        if (includeDesign) ...[
          const AppContextMenuDivider(),
          designItem(strings),
        ],
        if (extraEntries.isNotEmpty) ...[
          const AppContextMenuDivider(),
          ...extraEntries,
        ],
      ],
    );
  }

  /// Chart surface (or block caret on a chart table): design + column reorder.
  static Future<void> showChartMenu({
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
        AppContextMenuItem(
          value: 'object:move_mode',
          label: strings['moveObject'],
        ),
        const AppContextMenuDivider(),
        designItem(strings),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'table:reorder_columns',
          label: strings['reorderColumns'],
        ),
      ],
    );
  }

  /// Info field: formatting + Connect info.
  static Future<void> showInfoFieldMenu({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required DocumentMenuHandler onAction,
    bool includeDisconnectInfo = false,
  }) {
    return showTextMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      includeConnectInfo: true,
      includeDisconnectInfo: includeDisconnectInfo,
    );
  }

  /// Info chrome (block caret): Add tag + Add connection (related).
  static Future<void> showInfoChromeMenu({
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
        AppContextMenuItem(
          value: 'object:move_mode',
          label: strings['moveObject'],
        ),
        const AppContextMenuDivider(),
        designItem(strings),
        const AppContextMenuDivider(),
        AppContextMenuItem(value: 'info:add_tag', label: strings['addTag']),
        AppContextMenuItem(
          value: 'info:add_connection',
          label: strings['addConnection'],
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
    return showInfoChromeMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
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
    bool includeConnectInfo = false,
    bool includeDisconnectInfo = false,
  }) {
    return _showMenu(
      context: context,
      globalPosition: globalPosition,
      strings: strings,
      onAction: onAction,
      entries: [
        AppContextMenuItem(
          value: 'object:move_mode',
          label: strings['moveObject'],
        ),
        const AppContextMenuDivider(),
        ...buildTextEntries(
          strings,
          includeConnectInfo: includeConnectInfo,
          includeDisconnectInfo: includeDisconnectInfo,
        ),
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
