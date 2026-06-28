import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/block.dart';
import '../../core/registry/file_behavior_registry.dart';
import '../../shared/widgets/app_context_menu.dart';
import 'block_text_focus.dart';
import 'format_range.dart';

typedef BlockMenuHandler = Future<void> Function(String action);

class BlockContextMenu {
  const BlockContextMenu._();

  static Future<String?> show({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required String fileType,
    required int orderIndex,
    Block? targetBlock,
    BlockMenuHandler? onAction,
  }) async {
    final controller = BlockTextFocusRegistry.activeController;
    if (controller != null) {
      FormatRange.capturePending(controller.text, controller.selection);
    }
    BlockTextFocusRegistry.openMenuSession();
    try {
      final entries = <AppContextMenuEntry>[];
      final insertTypes =
          FileBehaviorRegistry.contextMenuForFileType(fileType);
      if (insertTypes.isNotEmpty) {
        entries.add(
          AppContextMenuSubmenu(
            label: strings['addBlock'],
            children: [
              for (final type in insertTypes)
                AppContextMenuItem(
                  value: 'insert:$type',
                  label: _insertLabel(type, strings),
                ),
            ],
          ),
        );
      }

      if (targetBlock != null) {
        entries.add(const AppContextMenuDivider());
        entries.addAll(_blockActions(targetBlock, strings));
      }

      if (BlockTextFocusRegistry.hasFocus) {
        entries
          ..add(const AppContextMenuDivider())
          ..addAll(_textActions(strings));
      }

      final value = await AppContextMenu.show(
        context: context,
        globalPosition: globalPosition,
        entries: entries,
        isRtl: strings.isRtl,
      );
      if (value == null) return null;
      if (value.startsWith('text:')) {
        await _handleTextAction(value);
        return value;
      }
      await onAction?.call(value);
      return value;
    } finally {
      BlockTextFocusRegistry.closeMenuSession();
    }
  }

  static List<AppContextMenuEntry> _blockActions(
    Block block,
    AppStrings strings,
  ) {
    final items = <AppContextMenuEntry>[
      AppContextMenuItem(
        value: 'delete_block',
        label: strings['deleteBlock'],
        destructive: true,
      ),
    ];

    switch (block.type) {
      case 'list':
        final style = block.content['list_style'] as String? ?? 'bullet';
        items.add(
          AppContextMenuItem(
            value: style == 'bullet' ? 'list:numbered' : 'list:bullet',
            label: style == 'bullet'
                ? strings['numberedList']
                : strings['bulletList'],
          ),
        );
      case 'table':
        items.addAll([
          AppContextMenuItem(value: 'table:row', label: strings['addRow']),
          AppContextMenuItem(
            value: 'table:column',
            label: strings['addColumn'],
          ),
        ]);
      case 'graph':
        items.addAll([
          AppContextMenuItem(
            value: 'graph:add_variable',
            label: strings['graphAddVariable'],
          ),
          AppContextMenuItem(
            value: 'graph:remove_variable',
            label: strings['graphRemoveVariable'],
          ),
          const AppContextMenuDivider(),
          AppContextMenuItem(
            value: 'graph:colors',
            label: strings['graphChangeColors'],
          ),
          const AppContextMenuDivider(),
          AppContextMenuItem(value: 'graph:bar', label: strings['graphBar']),
          AppContextMenuItem(value: 'graph:line', label: strings['graphLine']),
          AppContextMenuItem(value: 'graph:pie', label: strings['graphPie']),
        ]);
      case 'image':
        items.addAll([
          AppContextMenuItem(value: 'image:replace', label: strings['replaceImage']),
          AppContextMenuItem(
            value: 'image:reset_width',
            label: strings['resetImageWidth'],
          ),
        ]);
      default:
        break;
    }
    return items;
  }

  static List<AppContextMenuEntry> _textActions(AppStrings strings) =>
      [
        AppContextMenuItem(value: 'text:cut', label: strings['cut']),
        AppContextMenuItem(value: 'text:copy', label: strings['copy']),
        AppContextMenuItem(value: 'text:paste', label: strings['paste']),
        const AppContextMenuDivider(),
        AppContextMenuItem(value: 'text:bold', label: strings['bold']),
        AppContextMenuItem(value: 'text:italic', label: strings['italic']),
        AppContextMenuItem(value: 'text:underline', label: strings['underline']),
        AppContextMenuItem(value: 'text:size_up', label: strings['textSizeUp']),
        AppContextMenuItem(value: 'text:size_down', label: strings['textSizeDown']),
      ];

  static Future<void> _handleTextAction(String value) async {
    switch (value) {
      case 'text:cut':
        await BlockTextFocusRegistry.cut();
      case 'text:copy':
        await BlockTextFocusRegistry.copy();
      case 'text:paste':
        await BlockTextFocusRegistry.paste();
      case 'text:bold':
      case 'text:italic':
      case 'text:underline':
      case 'text:size_up':
      case 'text:size_down':
        BlockTextFocusRegistry.applyTextFormat(value);
    }
  }

  static String _insertLabel(String type, AppStrings s) {
    switch (type) {
      case 'text':
        return s['addText'];
      case 'header':
        return s['addHeader'];
      case 'summary':
        return s['addSummary'];
      case 'image':
        return s['addImage'];
      case 'table':
        return s['addTable'];
      case 'list':
        return s['addList'];
      case 'graph':
        return s['addGraph'];
      case 'task_list':
        return s['addTaskList'];
      default:
        return type;
    }
  }
}
