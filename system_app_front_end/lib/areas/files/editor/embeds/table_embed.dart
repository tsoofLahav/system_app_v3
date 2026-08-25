import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/app_state.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/data/table_payload.dart';
import '../../../ui/app_color_palettes.dart';
import '../../../ux/topic/topic_appearance.dart';
import '../../model/document_model.dart';
import '../../rich_text/connect_info.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/rich_table_editor.dart';
import '../document_secondary_tap.dart';
import '../document_text_flow.dart';
import '../edit_conflict.dart';
import '../editor_key_handoff.dart';
import '../embed_caret_bridge.dart';
import './table_chart.dart';

/// Table object embed — [RichTableEditor] (+ optional chart chrome).
class TableEmbed extends StatefulWidget {
  const TableEmbed({
    super.key,
    required this.embed,
    required this.blockId,
    required this.state,
    required this.onPayloadChanged,
    this.onFocus,
    this.onDeleteObject,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppState state;
  AppStrings get strings => state.strings;
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
  late Map<String, dynamic> _baseline;
  var _dirty = false;
  var _conflictOpen = false;
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
    _baseline = _payload;
    widget.state.addListener(_onAppState);
  }

  @override
  void didUpdateWidget(TableEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embed.id != widget.embed.id) {
      _setDirty(false);
      _payload = TableObjectPayload.normalize(widget.embed.payload);
      _baseline = _payload;
      return;
    }
    _considerInbound(TableObjectPayload.normalize(widget.embed.payload));
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
    widget.state.removeListener(_onAppState);
    _saveTimer?.cancel();
    if (_shouldFlushOnDispose()) {
      widget.onPayloadChanged(_payload);
    }
    UnsavedEmbedEdits.mark(widget.embed.id, false);
    _registry?.unregister(nodeId);
    _registry = null;
    super.dispose();
  }

  ObjectEmbed? get _cachedEmbed {
    final list = widget.state.embedsByFileId[widget.embed.fileId];
    if (list == null) return null;
    for (final embed in list) {
      if (embed.id == widget.embed.id) return embed;
    }
    return null;
  }

  void _onAppState() {
    if (!mounted) return;
    final cached = _cachedEmbed;
    if (cached == null) return;
    _considerInbound(TableObjectPayload.normalize(cached.payload));
  }

  void _setDirty(bool value) {
    if (_dirty == value) return;
    _dirty = value;
    UnsavedEmbedEdits.mark(widget.embed.id, value);
  }

  bool _shouldFlushOnDispose() {
    if (!_dirty) return false;
    final cached = TableObjectPayload.normalize(_cachedEmbed?.payload);
    if (jsonEquals(cached, _payload)) return false;
    // Cache moved to something that is not our last save — agent wrote.
    if (!jsonEquals(cached, _baseline)) return false;
    return true;
  }

  void _considerInbound(Map<String, dynamic> inbound) {
    if (UnsavedEmbedEdits.takeLocalOverInbound && _dirty) {
      UnsavedEmbedEdits.takeLocalOverInbound = false;
      _persistNow();
      return;
    }
    final decision = decideRemoteEdit(
      localDirty: _dirty,
      inboundEqualsLocal: jsonEquals(inbound, _payload),
      inboundEqualsBaseline: jsonEquals(inbound, _baseline),
    );
    switch (decision) {
      case RemoteEditDecision.ignore:
        return;
      case RemoteEditDecision.takeRemote:
        _applyRemote(inbound);
        return;
      case RemoteEditDecision.ask:
        if (UnsavedEmbedEdits.fileConflictPending) return;
        _askConflict(inbound);
        return;
    }
  }

  void _applyRemote(Map<String, dynamic> inbound) {
    _saveTimer?.cancel();
    _setDirty(false);
    _payload = inbound;
    _baseline = inbound;
    void paint() {
      if (!mounted) return;
      if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
        runAfterKeystroke(paint);
        return;
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorKey.currentState?.syncFromNode(force: true);
      });
    }

    paint();
  }

  void _askConflict(Map<String, dynamic> inbound) {
    if (_conflictOpen) return;
    void run() async {
      if (!mounted || _conflictOpen) return;
      _conflictOpen = true;
      final choice = await showEditConflictDialog(
        context: context,
        strings: widget.strings,
      );
      _conflictOpen = false;
      if (!mounted) return;
      if (choice == EditConflictChoice.keepYours) {
        _persistNow();
        return;
      }
      _applyRemote(inbound);
    }

    if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      runAfterKeystroke(run);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
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
    _setDirty(true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _persistNow();
    });
  }

  void _persistNow() {
    _saveTimer?.cancel();
    widget.onPayloadChanged(_payload);
    _baseline = _payload;
    _setDirty(false);
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
          onConnectInfo: () async {
            await connectInfoFromMark(
              context: context,
              state: widget.state,
              host: widget.embed,
            );
            if (mounted) setState(() {});
          },
          descriptionRangesForCell: (r, c) => descriptionRangesForSegment(
            state: widget.state,
            fileId: widget.embed.fileId,
            segmentId: tableCellSegmentId(widget.blockId, r, c),
          ),
          onDescriptionActivate: (range) => openDescriptionTarget(
            state: widget.state,
            link: range.link,
          ),
        ),
      ],
    );
  }
}
