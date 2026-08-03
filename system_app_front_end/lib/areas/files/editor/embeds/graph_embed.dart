import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../document_text_flow.dart';
import '../../rich_text/block_text_actions.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/formatted_text_field.dart';
import '../../rich_text/span_text_editing_controller.dart';
import '../../../ui/app_color_palettes.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/app_typography.dart';
import '../../../ux/topic/topic_appearance.dart';
import '../../../ux/widgets/app_context_menu.dart';
import '../../../objects/data/object_embed.dart';

/// Graph = chart + a two-row table whose **columns** grow like a table's rows.
///
/// Keyboard and caret follow [RichTableEditor]. Chart type and a **per-variable
/// colour palette** live in the payload (`colors[]`); edited from the chart
/// right-click menu.
class GraphEmbed extends StatefulWidget {
  const GraphEmbed({
    super.key,
    required this.embed,
    required this.blockId,
    required this.onPayloadChanged,
    required this.strings,
    this.onFocus,
    this.onExitBelow,
  });

  final ObjectEmbed embed;
  final String blockId;
  final ValueChanged<Map<String, dynamic>> onPayloadChanged;
  final AppStrings strings;
  final VoidCallback? onFocus;

  /// Empty column index — parent drops it and continues as a paragraph below.
  final ValueChanged<int>? onExitBelow;

  @override
  State<GraphEmbed> createState() => _GraphEmbedState();
}

class _GraphEmbedState extends State<GraphEmbed> {
  late List<List<SpanTextEditingController>> _cells;
  late List<List<FocusNode>> _focus;
  late String _chartType;
  late List<String> _colorHexes;

  static const _defaultColumns = 2;
  static const _minCellHeight = 36.0;
  static const _maxColumns = AppColorPalettes.seriesLimit;

  String _defaultColorAt(int index) {
    final hexes = AppColorPalettes.defaultChart.hexes;
    return hexes[index % hexes.length];
  }

  @override
  void initState() {
    super.initState();
    _buildFromPayload(widget.embed.payload);
  }

  @override
  void didUpdateWidget(GraphEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embed.id != widget.embed.id) {
      _disposeGrid();
      _buildFromPayload(widget.embed.payload);
      return;
    }

    final incoming = widget.embed.payload;
    final incomingCols = _labelList(incoming).length;
    final incomingType = _readChartType(incoming);
    final incomingColors = _readColors(incoming, incomingCols);

    if (incomingCols != _columnCount) {
      final hadFocus = _anyFocused;
      var focusRow = 0;
      var focusCol = 0;
      if (hadFocus) {
        for (var r = 0; r < _focus.length; r++) {
          for (var c = 0; c < _focus[r].length; c++) {
            if (_focus[r][c].hasFocus) {
              focusRow = r;
              focusCol = c;
            }
          }
        }
      }
      _disposeGrid();
      _buildFromPayload(incoming);
      // Exit-below unfocuses first — do not steal the caret back.
      if (hadFocus && _columnCount > 0) {
        _focusCell(focusRow.clamp(0, 1), focusCol.clamp(0, _columnCount - 1));
      }
      return;
    }

    if (incomingType != _chartType ||
        !_sameHexList(incomingColors, _colorHexes)) {
      setState(() {
        _chartType = incomingType;
        _colorHexes = incomingColors;
      });
    }

    if (_anyFocused) return;
    if (_matchesPayload(incoming)) return;
    _disposeGrid();
    _buildFromPayload(incoming);
  }

  bool get _anyFocused {
    for (final row in _focus) {
      for (final node in row) {
        if (node.hasFocus) return true;
      }
    }
    return false;
  }

  int get _columnCount => _cells.isEmpty ? 0 : _cells.first.length;

  List<Color> get _chartColors => [
        for (final hex in _colorHexes) TopicAppearance.colorFromHex(hex),
      ];

  void _unfocusAll() {
    for (final row in _focus) {
      for (final node in row) {
        if (node.hasFocus) node.unfocus();
      }
    }
  }

  Map<String, dynamic> _payloadFromCells() {
    _syncColorCount();
    return {
      ...?widget.embed.payload,
      'labels': [for (final c in _cells[0]) c.text],
      'values': [for (final c in _cells[1]) c.text],
      'chartType': _chartType,
      'colors': List<String>.from(_colorHexes),
      // Legacy single colour — first variable — for older readers.
      'color': _colorHexes.isEmpty ? _defaultColorAt(0) : _colorHexes.first,
    };
  }

  bool _matchesPayload(Map<String, dynamic>? payload) {
    final labels = _labelList(payload);
    final values = _valueList(payload, labels.length);
    if (_columnCount != labels.length) return false;
    if (_readChartType(payload) != _chartType) return false;
    if (!_sameHexList(_readColors(payload, labels.length), _colorHexes)) {
      return false;
    }
    for (var c = 0; c < labels.length; c++) {
      if (_cells[0][c].text != labels[c]) return false;
      if (_cells[1][c].text != values[c]) return false;
    }
    return true;
  }

  bool _sameHexList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (AppColors.normalizeHex(a[i]) != AppColors.normalizeHex(b[i])) {
        return false;
      }
    }
    return true;
  }

  void _syncColorCount() {
    while (_colorHexes.length < _columnCount) {
      _colorHexes.add(_defaultColorAt(_colorHexes.length));
    }
    if (_colorHexes.length > _columnCount) {
      _colorHexes = _colorHexes.sublist(0, _columnCount);
    }
  }

  List<String> _labelList(Map<String, dynamic>? payload) {
    final raw = payload?['labels'];
    if (raw is! List || raw.isEmpty) {
      return List.filled(_defaultColumns, '');
    }
    final all = [for (final e in raw) '$e'];
    if (all.length > _maxColumns) return all.sublist(0, _maxColumns);
    return all;
  }

  List<String> _valueList(Map<String, dynamic>? payload, int length) {
    final raw = payload?['values'];
    final out = <String>[];
    if (raw is List) {
      for (final v in raw) {
        out.add(v is num ? _formatNum(v) : '$v');
      }
    }
    while (out.length < length) {
      out.add('');
    }
    return out.sublist(0, length);
  }

  String _formatNum(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
  }

  String _readChartType(Map<String, dynamic>? payload) {
    final raw = payload?['chartType'] ?? payload?['chart_type'];
    return switch (raw) {
      'line' || 'pie' || 'bar' => '$raw',
      _ => 'bar',
    };
  }

  List<String> _readColors(Map<String, dynamic>? payload, int length) {
    final out = <String>[];
    final raw = payload?['colors'];
    if (raw is List) {
      for (final e in raw) {
        final hex = '$e'.trim();
        if (hex.isNotEmpty) out.add(AppColors.normalizeHex(hex));
      }
    }
    final legacy = payload?['color'];
    final legacyHex = legacy is String && legacy.trim().isNotEmpty
        ? AppColors.normalizeHex(legacy.trim())
        : null;
    while (out.length < length) {
      final i = out.length;
      out.add(i == 0 && legacyHex != null ? legacyHex : _defaultColorAt(i));
    }
    return out.sublist(0, length);
  }

  void _buildFromPayload(Map<String, dynamic>? payload) {
    final labels = _labelList(payload);
    final values = _valueList(payload, labels.length);
    _chartType = _readChartType(payload);
    _colorHexes = _readColors(payload, labels.length);
    _cells = [
      [for (final t in labels) SpanTextEditingController(text: t)],
      [for (final t in values) SpanTextEditingController(text: t)],
    ];
    _focus = [
      [for (var i = 0; i < labels.length; i++) FocusNode()],
      [for (var i = 0; i < labels.length; i++) FocusNode()],
    ];
  }

  void _disposeGrid() {
    for (final row in _focus) {
      for (final n in row) {
        if (n.hasFocus) n.unfocus();
      }
    }
    final cells = _cells;
    final focus = _focus;
    _cells = <List<SpanTextEditingController>>[];
    _focus = <List<FocusNode>>[];
    // Dispose after this frame so EditableText is not still observing
    // metrics while its element is deactivated (Flutter ancestor lookup).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in cells) {
        for (final c in row) {
          c.dispose();
        }
      }
      for (final row in focus) {
        for (final n in row) {
          n.dispose();
        }
      }
    });
  }

  @override
  void dispose() {
    // Do not PATCH on dispose — the object may already be deleted (empty
    // exit) and a late write throws "ObjectEmbed not found".
    _disposeGrid();
    super.dispose();
  }

  void _emit() {
    if (!mounted) return;
    widget.onFocus?.call();
    widget.onPayloadChanged(_payloadFromCells());
    setState(() {});
  }

  void _setChartType(String type) {
    if (_chartType == type) return;
    setState(() => _chartType = type);
    _emit();
  }

  void _applyPalette(String paletteId) {
    final palette = AppColorPalettes.byId(paletteId);
    if (palette == null) return;
    setState(() {
      _colorHexes = palette.colorsForCount(_columnCount);
    });
    _emit();
  }

  void _focusCell(int row, int col) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (row < 0 || row > 1 || col < 0 || col >= _columnCount) return;
      _focus[row][col].requestFocus();
    });
  }

  void _addColumnAfter(int col, {required int focusRow}) {
    if (_columnCount >= _maxColumns) return;
    setState(() {
      for (final row in _cells) {
        row.insert(col + 1, SpanTextEditingController(text: ''));
      }
      for (final row in _focus) {
        row.insert(col + 1, FocusNode());
      }
      _colorHexes.insert(col + 1, _defaultColorAt(_colorHexes.length));
    });
    _emit();
    _focusCell(focusRow, col + 1);
  }

  void _removeColumnAt(int col, {required int focusRow}) {
    if (_columnCount <= 1) {
      _unfocusAll();
      widget.onExitBelow?.call(col);
      return;
    }
    setState(() {
      for (final row in _cells) {
        row.removeAt(col).dispose();
      }
      for (final row in _focus) {
        row.removeAt(col).dispose();
      }
      if (col < _colorHexes.length) _colorHexes.removeAt(col);
    });
    _emit();
    _focusCell(focusRow, col.clamp(0, _columnCount - 1));
  }

  bool _columnIsEmpty(int col) {
    return _cells[0][col].text.trim().isEmpty &&
        _cells[1][col].text.trim().isEmpty;
  }

  void _exitFromColumn(int col) {
    _unfocusAll();
    widget.onExitBelow?.call(col);
  }

  KeyEventResult _onKey(KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onFocus?.call();
      if (_columnIsEmpty(col)) {
        _exitFromColumn(col);
        return KeyEventResult.handled;
      }
      if (col + 1 < _columnCount) {
        _focusCell(row, col + 1);
      } else {
        _addColumnAfter(col, focusRow: row);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (row == 0) {
        _focusCell(1, col);
      } else if (col + 1 < _columnCount) {
        _focusCell(0, col + 1);
      } else {
        _focusCell(0, 0);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = _cells[row][col];
      final sel = controller.selection;
      final atStart = !sel.isValid || (sel.isCollapsed && sel.baseOffset <= 0);
      if (atStart && controller.text.isEmpty && _columnIsEmpty(col)) {
        widget.onFocus?.call();
        _removeColumnAt(col, focusRow: row);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _showChartMenu(TapDownDetails details) async {
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: details.globalPosition,
      isRtl: widget.strings.isRtl,
      entries: [
        AppContextMenuItem(
          value: 'type:bar',
          label: widget.strings['graphBar'],
        ),
        AppContextMenuItem(
          value: 'type:line',
          label: widget.strings['graphLine'],
        ),
        AppContextMenuItem(
          value: 'type:pie',
          label: widget.strings['graphPie'],
        ),
        const AppContextMenuDivider(),
        AppContextMenuSubmenu(
          label: widget.strings['graphChangeColors'],
          children: [
            for (final palette in AppColorPalettes.chart)
              AppContextMenuItem(
                value: 'palette:${palette.id}',
                label: widget.strings[palette.nameKey],
              ),
          ],
        ),
      ],
    );
    if (!mounted || value == null) return;
    if (value.startsWith('palette:')) {
      _applyPalette(value.substring('palette:'.length));
      return;
    }
    if (value.startsWith('type:')) {
      _setChartType(value.substring('type:'.length));
    }
  }

  Future<void> _showCellMenu(TapDownDetails details, int row, int col) async {
    await DocumentContextMenu.showTableCellMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.strings,
      onAction: (action) async {
        if (action == 'table:add_column') {
          _addColumnAfter(col, focusRow: row);
          return;
        }
        await runBlockTextAction(action);
      },
    );
  }

  List<double> get _values => [
        for (final c in _cells[1]) double.tryParse(c.text.trim()) ?? 0.0,
      ];

  @override
  Widget build(BuildContext context) {
    final values = _values;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Color.alphaBlend(
      scheme.outline.withValues(alpha: 0.55),
      scheme.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onSecondaryTapDown: _showChartMenu,
          child: SizedBox(
            height: 88,
            child: _ChartView(
              type: _chartType,
              values: values,
              labels: [for (final c in _cells[0]) c.text],
              colors: _chartColors,
              // Match the table: in Hebrew, column 0 sits on the right.
              textDirection: Directionality.of(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var r = 0; r < 2; r++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < _columnCount; c++) ...[
                        if (c > 0)
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: borderColor,
                          ),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: r == 0
                                    ? BorderSide(color: borderColor, width: 1)
                                    : BorderSide.none,
                              ),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: _minCellHeight,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Focus(
                                  onKeyEvent: (node, event) =>
                                      _onKey(event, r, c),
                                  child: FormattedTextField(
                                    controller: _cells[r][c],
                                    focusNode: _focus[r][c],
                                    segmentId: graphCellSegmentId(
                                      widget.blockId,
                                      r,
                                      c,
                                    ),
                                    style: AppTypography.documentParagraphStyle,
                                    hintText: r == 0 && c == 0
                                        ? widget.strings['graphAddVariable']
                                        : null,
                                    maxLines: null,
                                    minLines: 1,
                                    onChanged: (_) => _emit(),
                                    onSecondaryTapDown: (d) =>
                                        _showCellMenu(d, r, c),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartView extends StatelessWidget {
  const _ChartView({
    required this.type,
    required this.values,
    required this.labels,
    required this.colors,
    required this.textDirection,
  });

  final String type;
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final TextDirection textDirection;

  Color _colorAt(int i) {
    if (colors.isEmpty) return AppColors.primary;
    return colors[i % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.expand();
    }
    final resolved = [for (var i = 0; i < values.length; i++) _colorAt(i)];
    return CustomPaint(
      painter: switch (type) {
        'line' => _LineChartPainter(
            values: values,
            colors: resolved,
            textDirection: textDirection,
          ),
        'pie' => _PieChartPainter(
            values: values,
            colors: resolved,
            textDirection: textDirection,
          ),
        _ => _BarChartPainter(
            values: values,
            colors: resolved,
            textDirection: textDirection,
          ),
      },
      child: const SizedBox.expand(),
    );
  }
}

/// Visual slot for logical index [i] so series 0 sits on the reading-start side
/// (left in LTR, right in RTL) — same as the table columns below.
int _visualSlot(int i, int count, TextDirection direction) {
  if (count <= 0) return 0;
  return direction == TextDirection.rtl ? count - 1 - i : i;
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal =
        values.fold<double>(0, (a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final gap = size.width / values.length;
    final barWidth = gap * 0.55;
    for (var i = 0; i < values.length; i++) {
      final slot = _visualSlot(i, values.length, textDirection);
      final h = (values[i] / maxVal).clamp(0.04, 1.0) * size.height;
      final left = gap * slot + (gap - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barWidth, h),
          const Radius.circular(2),
        ),
        Paint()..color = colors[i].withValues(alpha: 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal =
        values.fold<double>(0, (a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final dx =
        values.length == 1 ? size.width / 2 : size.width / (values.length - 1);
    Offset point(int i) {
      final slot = _visualSlot(i, values.length, textDirection);
      final x = values.length == 1 ? size.width / 2 : dx * slot;
      final y = size.height -
          (values[i] / maxVal).clamp(0.0, 1.0) * (size.height - 4) -
          2;
      return Offset(x, y);
    }

    // Draw segments in visual order so the stroke follows the reading direction.
    final order = [
      for (var slot = 0; slot < values.length; slot++)
        textDirection == TextDirection.rtl ? values.length - 1 - slot : slot,
    ];
    for (var s = 0; s < order.length - 1; s++) {
      final a = order[s];
      final b = order[s + 1];
      canvas.drawLine(
        point(a),
        point(b),
        Paint()
          ..color = colors[a]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 3, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + (b < 0 ? 0 : b));
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: math.min(size.width, size.height) - 8,
      height: math.min(size.width, size.height) - 8,
    );
    if (total <= 0) {
      canvas.drawOval(
        rect,
        Paint()..color = colors.first.withValues(alpha: 0.2),
      );
      return;
    }
    // RTL: walk slices the other way so the first variable stays at the start.
    final indices = [
      for (var i = 0; i < values.length; i++)
        textDirection == TextDirection.rtl ? values.length - 1 - i : i,
    ];
    var start = -math.pi / 2;
    for (final i in indices) {
      final sweep = (values[i].clamp(0, double.infinity) / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i].withValues(alpha: 0.85),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}
