import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/block.dart';
import '../../core/registry/file_behavior_registry.dart';
import '../../shared/widgets/app_context_menu.dart';
import 'block_text_focus.dart';
import 'block_text_actions.dart';
import 'format_range.dart';
import 'text_emoji_picker.dart';

typedef BlockMenuHandler = Future<void> Function(String action);

class BlockContextMenu {
  const BlockContextMenu._();

  /// File/block rows for a context menu (add block, block actions). Omits
  /// text-format actions unless [includeTextActions] and a field has focus.
  static List<AppContextMenuEntry> buildFileEntries({
    required AppStrings strings,
    required String fileType,
    Block? targetBlock,
    bool includeTextActions = true,
    bool supportsParts = false,
    bool hasAvailableParts = false,
  }) {
    final entries = <AppContextMenuEntry>[];
    if (supportsParts) {
      entries.add(
        AppContextMenuSubmenu(
          label: strings['addPart'],
          children: [
            AppContextMenuItem(
              value: 'part:new',
              label: strings['addNewPart'],
            ),
            AppContextMenuItem(
              value: 'part:existing',
              label: strings['addExistingPart'],
              enabled: hasAvailableParts,
            ),
          ],
        ),
      );
    }
    final insertTypes =
        FileBehaviorRegistry.contextMenuForFileType(fileType);
    if (insertTypes.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(const AppContextMenuDivider());
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
      if (entries.isNotEmpty) entries.add(const AppContextMenuDivider());
      entries.addAll(_blockActions(targetBlock, strings));
    }

    if (includeTextActions && BlockTextFocusRegistry.hasFocus) {
      entries
        ..add(const AppContextMenuDivider())
        ..addAll(_textActions(strings));
    }
    return entries;
  }

  static Future<String?> show({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required String fileType,
    required int orderIndex,
    AppState? appState,
    Block? targetBlock,
    bool supportsParts = false,
    bool hasAvailableParts = false,
    BlockMenuHandler? onAction,
  }) async {
    AppContextMenu.dismissActive();
    final controller = BlockTextFocusRegistry.activeController;
    if (controller != null) {
      FormatRange.capturePending(controller.text, controller.selection);
    }
    BlockTextFocusRegistry.openMenuSession();
    String? value;
    try {
      final entries = buildFileEntries(
        strings: strings,
        fileType: fileType,
        targetBlock: targetBlock,
        supportsParts: supportsParts,
        hasAvailableParts: hasAvailableParts,
      );

      value = await AppContextMenu.show(
        context: context,
        globalPosition: globalPosition,
        entries: entries,
        isRtl: strings.isRtl,
      );
      if (value == null) return null;
      if (value.startsWith('text:') &&
          value != 'text:emoji' &&
          value != 'text:suggest_emoji') {
        await runBlockTextAction(value);
      } else if (value != 'text:emoji' && value != 'text:suggest_emoji') {
        await onAction?.call(value);
      }
    } finally {
      BlockTextFocusRegistry.closeMenuSession();
    }
    if (value == 'text:emoji' && context.mounted) {
      await showTextEmojiPicker(
        context: context,
        searchHint: strings['searchEmoji'],
        title: strings['insertEmoji'],
      );
    }
    if (value == 'text:suggest_emoji' && context.mounted && appState != null) {
      await runSuggestEmoji(context, appState);
    }
    return value;
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
          AppContextMenuItem(
            value: 'table:row:before',
            label: strings['addRowAbove'],
          ),
          AppContextMenuItem(
            value: 'table:row:after',
            label: strings['addRowBelow'],
          ),
          AppContextMenuItem(
            value: 'table:column:before',
            label: strings['addColumnBefore'],
          ),
          AppContextMenuItem(
            value: 'table:column:after',
            label: strings['addColumnAfter'],
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
        AppContextMenuItem(value: 'text:emoji', label: strings['insertEmoji']),
        AppContextMenuItem(
          value: 'text:suggest_emoji',
          label: strings['aiSuggestEmoji'],
          enabled: BlockTextFocusRegistry.hasMarkedText,
        ),
        const AppContextMenuDivider(),
        AppContextMenuItem(value: 'text:bold', label: strings['bold']),
        AppContextMenuItem(value: 'text:italic', label: strings['italic']),
        AppContextMenuItem(value: 'text:underline', label: strings['underline']),
        AppContextMenuItem(value: 'text:size_up', label: strings['textSizeUp']),
        AppContextMenuItem(value: 'text:size_down', label: strings['textSizeDown']),
      ];

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
