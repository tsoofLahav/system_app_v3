import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/data/table_payload.dart';
import '../../../ui/app_color_palettes.dart';
import '../../../ux/topic/topic_appearance.dart';
import '../../model/document_model.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/rich_table_editor.dart';
import '../document_secondary_tap.dart';
import '../embed_caret_bridge.dart';
import './table_chart.dart';

/// Table object embed — [RichTableEditor] (+ optional chart chrome).
class TableEmbed extends StatefulWidget {
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

  @override
  State<TableEmbed> createState() => TableEmbedState();
}

class TableEmbedState extends State<TableEmbed>
    with EmbedLineGatewayMixin
    implements EmbedCaretGateway {
  final _editorKey = GlobalKey<RichTableEditorState>();
  EmbedCaretRegistry? _registry;
  late Map<String, dynamic> _payload;
  Timer? _saveTimer;

  @override
  String get nodeId => widget.blockId;

  @override
  int get lineCount => _editorKey.currentState?.lineCount ?? 0;

  @override
  void focusLine(int index, {required bool fromAbove}) {
    _editorKey.currentState?.focusLine(index, fromAbove: fromAbove);
  }

  @override
  void nudgeInner(AxisDirection direction) {
    _editorKey.currentState?.nudge(direction);
  }

  bool get _chartOn => TableObjectPayload.chartEnabled(_payload);

  bool get _editorBusy =>
      (_editorKey.currentState?.hasInnerFocus ?? false) ||
      (_editorKey.currentState?.reorderMode ?? false) ||
      HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _payload = TableObjectPayload.normalize(widget.embed.payload);
  }

  @override
  void didUpdateWidget(TableEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embed.id != widget.embed.id) {
      _payload = TableObjectPayload.normalize(widget.embed.payload);
      return;
    }
    // Controllers are live SoT while typing — never clobber with a cache patch.
    if (_editorBusy) return;
    if (oldWidget.embed.payload != widget.embed.payload) {
      _payload = TableObjectPayload.normalize(widget.embed.payload);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = EmbedCaretScope.maybeOf(context)?.registry;
    if (!identical(next, _registry)) {
      _registry?.unregister(nodeId);
      _registry = next;
      _registry?.register(this);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Best-effort flush of the last debounced cell edits.
    widget.onPayloadChanged(_payload);
    _registry?.unregister(nodeId);
    _registry = null;
    super.dispose();
  }

  TableNode _nodeFromPayload() {
    final rows = TableObjectPayload.rowsOf(_payload);
    return TableNode(
      id: widget.blockId,
      rows: [
        for (final row in rows)
          [
            for (final cell in row)
              DocumentTableCell(text: '${cell['text'] ?? ''}'),
          ],
      ],
    );
  }

  void _scheduleSave() {
    widget.onFocus?.call();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      widget.onPayloadChanged(_payload);
    });
  }

  void _persistNow() {
    _saveTimer?.cancel();
    widget.onPayloadChanged(_payload);
  }

  void _onRowsChanged(TableNode node) {
    final rows = [
      for (final row in node.rows)
        [
          for (final cell in row) {'text': cell.text},
        ],
    ];
    final next = Map<String, dynamic>.from(_payload)..['rows'] = rows;
    if (_chartOn) {
      final chart = Map<String, dynamic>.from(
        TableObjectPayload.chartOf(_payload) ?? {},
      );
      final cols = rows.isEmpty ? 0 : rows.first.length;
      final colors = List<String>.from(
        (chart['colors'] as List?)?.map((e) => '$e') ?? const [],
      );
      final hexes = AppColorPalettes.defaultChart.hexes;
      while (colors.length < cols) {
        colors.add(hexes[colors.length % hexes.length]);
      }
      if (colors.length > cols) {
        colors.removeRange(cols, colors.length);
      }
      chart['colors'] = colors;
      chart['enabled'] = true;
      next['chart'] = chart;
    }
    final oldRows = TableObjectPayload.rowsOf(_payload);
    _payload = TableObjectPayload.normalize(next);
    _scheduleSave();
    // Text-only emits must not rebuild the editor — that remounts cells and
    // drops the IME (language switch, clearing a cell). Chart chrome can wait
    // until the grid shape changes or the typing session ends.
    final shapeChanged =
        oldRows.length != rows.length ||
        (oldRows.isNotEmpty &&
            rows.isNotEmpty &&
            oldRows.first.length != rows.first.length);
    if (!shapeChanged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorBusy) return;
      setState(() {});
    });
  }

  /// Add column after the right-clicked / focused cell.
  @override
  void addColumnAfterCurrent() {
    _editorKey.currentState?.addColumnAfterCurrent();
  }

  @override
  void addRowAfterCurrent() {
    _editorKey.currentState?.addRowAfterCurrent();
  }

  @override
  void beginTableReorderRows() {
    _editorKey.currentState?.beginReorderRows();
  }

  @override
  void beginTableReorderColumns() {
    _editorKey.currentState?.beginReorderColumns();
  }

  /// Keep chart series colors aligned when a column is dragged.
  void _onReorderColumn(int from, int to) {
    if (!_chartOn || from == to) return;
    final chart = Map<String, dynamic>.from(
      TableObjectPayload.chartOf(_payload) ?? {'enabled': true},
    );
    final rows = TableObjectPayload.rowsOf(_payload);
    final cols = rows.isEmpty ? 0 : rows.first.length;
    final colors = List<String>.from(
      (chart['colors'] as List?)?.map((e) => '$e') ?? const [],
    );
    final hexes = AppColorPalettes.defaultChart.hexes;
    while (colors.length < cols) {
      colors.add(hexes[colors.length % hexes.length]);
    }
    if (from < 0 || to < 0 || from >= colors.length || to >= colors.length) {
      return;
    }
    final moved = colors.removeAt(from);
    colors.insert(to, moved);
    chart['colors'] = colors;
    chart['enabled'] = true;
    _payload = TableObjectPayload.normalize({..._payload, 'chart': chart});
  }

  void _setChartType(String type) {
    final chart = Map<String, dynamic>.from(
      TableObjectPayload.chartOf(_payload) ?? {'enabled': true},
    );
    chart['chartType'] = type;
    chart['enabled'] = true;
    setState(() {
      _payload = TableObjectPayload.normalize({..._payload, 'chart': chart});
    });
    _persistNow();
  }

  void _applyPalette(String paletteId) {
    final palette = AppColorPalettes.byId(paletteId);
    if (palette == null) return;
    final rows = TableObjectPayload.rowsOf(_payload);
    final cols = rows.isEmpty ? 0 : rows.first.length;
    final chart = Map<String, dynamic>.from(
      TableObjectPayload.chartOf(_payload) ?? {'enabled': true},
    );
    chart['colors'] = palette.colorsForCount(cols);
    chart['enabled'] = true;
    setState(() {
      _payload = TableObjectPayload.normalize({..._payload, 'chart': chart});
    });
    _persistNow();
  }

  Future<void> _onChartMenuAction(String action) async {
    if (action.startsWith('chart:type:')) {
      _setChartType(action.substring('chart:type:'.length));
      return;
    }
    if (action.startsWith('chart:palette:')) {
      _applyPalette(action.substring('chart:palette:'.length));
    }
  }

  Future<void> _showChartMenu(TapDownDetails details) async {
    DocumentSecondaryTap.markEmbedHandled();
    await DocumentContextMenu.showChartMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.strings,
      onAction: (action) async {
        if (action == 'table:reorder_columns') {
          beginTableReorderColumns();
          return;
        }
        await _onChartMenuAction(action);
      },
    );
  }

  void _onExitTable(int _) {
    // Escape leaves via EmbedEditScope; empty Enter exits via host Escape path.
  }

  @override
  Widget build(BuildContext context) {
    final chart = TableObjectPayload.chartOf(_payload);
    final chartOn = _chartOn;
    final rows = TableObjectPayload.rowsOf(_payload);
    final labels = rows.isNotEmpty
        ? [for (final c in rows[0]) '${c['text'] ?? ''}']
        : <String>[];
    final valueTexts = rows.length > 1
        ? [for (final c in rows[1]) '${c['text'] ?? ''}']
        : <String>[];
    final values = [for (final t in valueTexts) double.tryParse(t.trim()) ?? 0];
    final colorHexes = List<String>.from(
      (chart?['colors'] as List?)?.map((e) => '$e') ?? const [],
    );
    final colors = [
      for (var i = 0; i < values.length; i++)
        TopicAppearance.colorFromHex(
          i < colorHexes.length && colorHexes[i].isNotEmpty
              ? colorHexes[i]
              : AppColorPalettes.defaultChart.hexes[i %
                    AppColorPalettes.defaultChart.hexes.length],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chartOn)
          TableChartView(
            type: '${chart?['chartType'] ?? 'bar'}',
            values: values,
            labels: labels,
            colors: colors,
            textDirection: Directionality.of(context),
            onSecondaryTapDown: _showChartMenu,
          ),
        if (chartOn) const SizedBox(height: 6),
        RichTableEditor(
          key: _editorKey,
          node: _nodeFromPayload(),
          strings: widget.strings,
          mode: chartOn ? TableEditorMode.chartSeries : TableEditorMode.grid,
          maxColumns: chartOn ? AppColorPalettes.seriesLimit : null,
          onChanged: _onRowsChanged,
          onFocus: widget.onFocus,
          onExitTable: _onExitTable,
          onDeleteTable: widget.onDeleteObject,
          onReorderColumn: chartOn ? _onReorderColumn : null,
          extraMenuEntries: chartOn
              ? DocumentContextMenu.buildChartEntries(widget.strings)
              : const [],
          onExtraMenuAction: chartOn ? _onChartMenuAction : null,
        ),
      ],
    );
  }
}
