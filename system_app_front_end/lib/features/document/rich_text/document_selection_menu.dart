import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/app_context_menu.dart';
import '../inline_document_model.dart';
import 'document_context_menu.dart';
import 'list_text_parse.dart';

final _listLinePrefix = RegExp(r'^\s*(?:[•\-\*]|\d+[\.\)])\s*');

bool isListLine(String line) => _listLinePrefix.hasMatch(line);

typedef SelectionMenuHandler = Future<void> Function(String action);

class DocumentSelectionMenu {
  const DocumentSelectionMenu._();

  static List<AppContextMenuEntry> buildEntries({
    required AppStrings strings,
    required InlineDocument document,
    required int selectionStart,
    required int selectionEnd,
  }) {
    if (selectionStart >= selectionEnd) return const [];
    final entries = <AppContextMenuEntry>[];
    final spansList = _selectionSpansListRegion(document, selectionStart, selectionEnd);
    if (spansList || _looksLikeListLines(document, selectionStart, selectionEnd)) {
      entries.add(
        AppContextMenuItem(
          value: 'convert:task_list',
          label: strings['turnIntoTaskList'] ?? 'Turn into task list',
        ),
      );
    }
    if (!spansList) {
      entries.add(
        AppContextMenuItem(
          value: 'convert:info',
          label: strings['turnIntoInfo'] ?? 'Turn into info',
        ),
      );
    }
    return entries;
  }

  static bool _selectionSpansListRegion(
    InlineDocument doc,
    int start,
    int end,
  ) {
    for (final region in doc.regions) {
      if (region.kind == 'list' && region.start < end && region.end > start) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeListLines(
    InlineDocument doc,
    int start,
    int end,
  ) {
    final slice = doc.text.substring(start.clamp(0, doc.text.length), end.clamp(0, doc.text.length));
    final lines = slice.split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return false;
    return lines.every((line) => isListLine(line));
  }

  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition,
    required AppStrings strings,
    required List<AppContextMenuEntry> extraEntries,
    required DocumentMenuHandler onTextAction,
    required SelectionMenuHandler onSelectionAction,
  }) async {
    final entries = [
      ...DocumentContextMenu.buildTextEntries(strings),
      if (extraEntries.isNotEmpty) const AppContextMenuDivider(),
      ...extraEntries,
    ];
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
      isRtl: strings.isRtl,
    );
    if (value == null) return;
    if (value.startsWith('convert:')) {
      await onSelectionAction(value);
    } else {
      await onTextAction(value);
    }
  }
}
