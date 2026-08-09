import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../objects/data/object_embed.dart';
import '../../model/document_model.dart';
import '../../rich_text/rich_table_editor.dart';

/// Table object embed — hosts [RichTableEditor] against object payload rows.
class TableEmbed extends StatelessWidget {
  const TableEmbed({
    super.key,
    required this.embed,
    required this.blockId,
    required this.strings,
    required this.onPayloadChanged,
    this.onFocus,
    this.onDeleteObject,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppStrings strings;
  final ValueChanged<Map<String, dynamic>> onPayloadChanged;
  final VoidCallback? onFocus;
  final VoidCallback? onDeleteObject;

  TableNode _nodeFromPayload() {
    final raw = embed.payload?['rows'];
    final rows = <List<DocumentTableCell>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is! List) continue;
        rows.add([
          for (final cell in row)
            DocumentTableCell(
              text: cell is Map
                  ? '${cell['text'] ?? ''}'
                  : '$cell',
            ),
        ]);
      }
    }
    if (rows.isEmpty) {
      rows.add([
        const DocumentTableCell(text: ''),
        const DocumentTableCell(text: ''),
      ]);
    }
    return TableNode(id: blockId, rows: rows);
  }

  Map<String, dynamic> _payloadFromNode(TableNode node) {
    return {
      'rows': [
        for (final row in node.rows)
          [
            for (final cell in row) {'text': cell.text},
          ],
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return RichTableEditor(
      node: _nodeFromPayload(),
      strings: strings,
      onChanged: (next) => onPayloadChanged(_payloadFromNode(next)),
      onFocus: onFocus,
      onDeleteTable: onDeleteObject,
    );
  }
}

/// Helpers for default table object payloads.
class TableObjectPayload {
  static Map<String, dynamic> empty({int columns = 2}) => {
        'rows': [
          [
            for (var c = 0; c < columns; c++) {'text': ''},
          ],
        ],
      };

  static Map<String, dynamic> fromRowStrings(List<List<String>> rows) => {
        'rows': [
          for (final row in rows)
            [
              for (final cell in row) {'text': cell},
            ],
        ],
      };
}
