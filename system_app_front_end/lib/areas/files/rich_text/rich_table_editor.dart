import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_color_palettes.dart';
import '../../ui/app_typography.dart';
import '../editor/document_text_flow.dart';
import '../editor/editor_key_handoff.dart';
import '../model/document_model.dart';
import '../../ux/widgets/app_context_menu.dart';
import './block_text_actions.dart';
import './document_context_menu.dart';
import './formatted_text_field.dart';
import './span_text_editing_controller.dart';

/// Grid editing modes for [RichTableEditor].
enum TableEditorMode {
  /// Arbitrary rows × columns; Enter grows rows.
  grid,

  /// Fixed 2 rows (labels/values); Enter grows columns (series), capped.
  chartSeries,
}

class RichTableEditor extends StatefulWidget {
  const RichTableEditor({
    super.key,
    required this.node,
    required this.strings,
    required this.onChanged,
    this.onFocus,
    this.onExitTable,
    this.onDeleteTable,
    this.documentBaseOffset = 0,
    this.mode = TableEditorMode.grid,
    this.maxColumns,
    this.cellHint,
    this.extraMenuEntries = const [],
    this.onExtraMenuAction,
  });

  final TableNode node;
  final AppStrings strings;
  final ValueChanged<TableNode> onChanged;
  final VoidCallback? onFocus;
  final ValueChanged<int>? onExitTable;

  /// Backspace on the last empty row/column — remove the table from the file.
  final VoidCallback? onDeleteTable;

  /// Start of this table's fence in the marker-text buffer.
  final int documentBaseOffset;

  final TableEditorMode mode;

  /// Cap for [TableEditorMode.chartSeries] (defaults to series palette limit).
  final int? maxColumns;

  /// Hint for the first cell (e.g. graph variable hint).
  final String? cellHint;

  /// Extra rows on the cell menu (e.g. chart type / palette).
  final List<AppContextMenuEntry> extraMenuEntries;
  final Future<void> Function(String action)? onExtraMenuAction;

  @override
  State<RichTableEditor> createState() => RichTableEditorState();
}

class RichTableEditorState extends State<RichTableEditor> {
  late List<List<SpanTextEditingController>> _controllers;
  final _focusNodes = <FocusNode>[];

  static const _defaultColumns = 2;
  static const _minCellHeight = 36.0;

  /// True while a cell owns focus (used by [TableEmbed] to keep local SoT).
  bool get hasInnerFocus => _focusNodes.any((f) => f.hasFocus);

  @override
  void initState() {
    super.initState();
    _syncControllers();
    if (widget.node.rows.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
  }

  bool _localStateMatchesNode() {
    final rows = _normalizedRows;
    if (_controllers.length != rows.length) return false;
    for (var r = 0; r < rows.length; r++) {
      if (_controllers[r].length != rows[r].length) return false;
      for (var c = 0; c < rows[r].length; c++) {
        if (_controllers[r][c].text != rows[r][c].text) return false;
      }
    }
    return true;
  }

  @override
  void didUpdateWidget(RichTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _disposeAll();
      _syncControllers();
      return;
    }
    // Rows removed or replaced upstream (exit, undo, external update) must
    // reach the controllers, or the next edit re-emits the stale grid.
    if (_localStateMatchesNode()) return;
    // Never dispose TextFields mid-KeyDown — that desyncs HardwareKeyboard
    // ("KeyDownEvent … physical key is already pressed").
    if (hasInnerFocus ||
        HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      return;
    }
    final focusedIndex = _focusNodes.indexWhere((f) => f.hasFocus);
    _disposeAll();
    _syncControllers();
    if (focusedIndex >= 0) {
      final columns = _columnCount;
      final row = focusedIndex ~/ columns;
      final col = focusedIndex % columns;
      if (row < _controllers.length && col < _controllers[row].length) {
        _focusCell(row, col);
      }
    }
  }

  bool get _isChart => widget.mode == TableEditorMode.chartSeries;

  int get _maxColumns =>
      widget.maxColumns ??
      (_isChart ? AppColorPalettes.seriesLimit : 64);

  List<List<DocumentTableCell>> get _normalizedRows {
    if (widget.node.rows.isEmpty) {
      final rowCount = _isChart ? 2 : 1;
      return [
        for (var r = 0; r < rowCount; r++)
          [
            for (var c = 0; c < _defaultColumns; c++)
              const DocumentTableCell(text: ''),
          ],
      ];
    }
    final maxCols = widget.node.rows
        .map((row) => row.length)
        .fold(_defaultColumns, (a, b) => a > b ? a : b);
    var targetCols = maxCols < _defaultColumns ? _defaultColumns : maxCols;
    if (_isChart && targetCols > _maxColumns) targetCols = _maxColumns;
    final source = _isChart
        ? [
            widget.node.rows.isNotEmpty
                ? widget.node.rows[0]
                : <DocumentTableCell>[],
            widget.node.rows.length > 1
                ? widget.node.rows[1]
                : <DocumentTableCell>[],
          ]
        : widget.node.rows;
    return [
      for (final row in source)
        [
          for (var c = 0; c < targetCols; c++)
            c < row.length ? row[c] : const DocumentTableCell(text: ''),
        ],
    ];
  }

  void _syncControllers() {
    final rows = _normalizedRows;
    _controllers = [
      for (final row in rows)
        [
          for (final cell in row)
            SpanTextEditingController(
              text: cell.text,
              spans: cell.spans.map((s) => s.toJson()).toList(),
            ),
        ],
    ];
    if (_controllers.isEmpty) {
      _controllers = [
        [
          for (var c = 0; c < _defaultColumns; c++)
            SpanTextEditingController(text: ''),
        ],
      ];
    }
  }

  int get _columnCount => _controllers.isEmpty ? _defaultColumns : _controllers.first.length;

  void _disposeAll() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _focusNodes.clear();
  }

  @override
  void dispose() {
    _disposeAll();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.node.copyWith(
        rows: [
          for (var r = 0; r < _controllers.length; r++)
            [
              for (var c = 0; c < _controllers[r].length; c++)
                DocumentTableCell(
                  text: _controllers[r][c].text,
                  spans: [
                    for (final s in _controllers[r][c].spans)
                      TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
                  ],
                ),
            ],
        ],
      ),
    );
  }

  FocusNode _focusAt(int row, int col) {
    final index = row * _columnCount + col;
    while (_focusNodes.length <= index) {
      _focusNodes.add(FocusNode());
    }
    return _focusNodes[index];
  }

  int get lineCount => _controllers.length * _columnCount;

  void focusLine(int index, {required bool fromAbove}) {
    if (lineCount <= 0) return;
    final cols = _columnCount;
    final i = index.clamp(0, lineCount - 1);
    final row = i ~/ cols;
    final col = i % cols;
    final controller = _controllers[row][col];
    final len = controller.text.length;
    controller.selection = TextSelection.collapsed(
      offset: fromAbove ? 0 : len,
    );
    _focusAt(row, col).requestFocus();
  }

  /// Physical grid: ↓/↑ stay in the same column; ←/→ stay in the same row.
  /// Chart tables use the same mapping (Enter still grows columns).
  void _arrowVertical(int row, int col, {required bool goingDown}) {
    if (goingDown) {
      if (row + 1 < _controllers.length) {
        _focusCell(row + 1, col, atStart: true);
        return;
      }
      widget.onExitTable?.call(row);
      return;
    }
    if (row > 0) {
      _focusCell(row - 1, col, atStart: false);
      return;
    }
    // Top edge ↑ — leave the embed upward.
    widget.onExitTable?.call(-1);
  }

  void _arrowHorizontal(int row, int col, {required bool goingRight}) {
    if (goingRight) {
      if (col + 1 < _columnCount) {
        _focusCell(row, col + 1, atStart: true);
      }
      return;
    }
    if (col > 0) {
      _focusCell(row, col - 1, atStart: false);
    }
  }

  void _focusCell(int row, int col, {bool atStart = true}) {
    final controller = _controllers[row][col];
    final len = controller.text.length;
    controller.selection = TextSelection.collapsed(
      offset: atStart ? 0 : len,
    );
    _focusAt(row, col).requestFocus();
  }

  /// Flat focus indices are `row * columnCount + col` — rebuild after grid shape
  /// changes or two cells share a [FocusNode] (double caret).
  void _rebuildFocusNodes() {
    for (final f in _focusNodes) {
      f.dispose();
    }
    _focusNodes.clear();
  }

  void _addRowAfter(int row) {
    setState(() {
      _controllers.insert(
        row + 1,
        [
          for (var i = 0; i < _columnCount; i++)
            SpanTextEditingController(text: ''),
        ],
      );
      _rebuildFocusNodes();
    });
    _emit();
    runNextFrame(() {
      if (!mounted) return;
      _focusCell(row + 1, 0);
    });
  }

  void _addColumnAfter(int col, {required int focusRow}) {
    setState(() {
      for (final row in _controllers) {
        row.insert(col + 1, SpanTextEditingController(text: ''));
      }
      _rebuildFocusNodes();
    });
    _emit();
    // Next frame — let disposed focus nodes settle so only one caret shows.
    runNextFrame(() {
      if (!mounted) return;
      _focusCell(focusRow, (col + 1).clamp(0, _columnCount - 1));
    });
  }

  /// Block-caret “Add column” (no focused cell) — append on the right.
  void addColumnAtEnd() {
    if (_columnCount >= _maxColumns) return;
    final focusRow = _focusNodes.indexWhere((f) => f.hasFocus);
    final row = focusRow >= 0
        ? (focusRow ~/ _columnCount).clamp(0, _controllers.length - 1)
        : 0;
    _addColumnAfter(_columnCount - 1, focusRow: row);
  }

  bool _rowIsEmpty(int row) {
    return _controllers[row].every((c) => c.text.trim().isEmpty);
  }

  bool _columnIsEmpty(int col) {
    if (_controllers.isEmpty || col < 0 || col >= _columnCount) return true;
    return _controllers.every(
      (row) => col >= row.length || row[col].text.trim().isEmpty,
    );
  }

  /// Backspace on an empty row removes it; the last empty row deletes the table
  /// (fluent text). Enter on empty still uses [onExitTable].
  void _removeRowAt(int row) {
    widget.onFocus?.call();
    if (row < 0 || row >= _controllers.length) return;
    if (!_rowIsEmpty(row)) return;
    if (_controllers.length <= 1) {
      (widget.onDeleteTable ?? () => widget.onExitTable?.call(row))();
      return;
    }
    setState(() {
      for (final c in _controllers.removeAt(row)) {
        c.dispose();
      }
      for (final f in _focusNodes) {
        f.dispose();
      }
      _focusNodes.clear();
    });
    _emit();
    final focusRow = (row > 0 ? row - 1 : 0).clamp(0, _controllers.length - 1);
    _focusCell(focusRow, 0);
  }

  void _removeColumnAt(int col, {required int focusRow}) {
    widget.onFocus?.call();
    if (_columnCount <= 1) {
      runAfterKeystroke(() {
        if (!mounted) return;
        (widget.onDeleteTable ?? () => widget.onExitTable?.call(col))();
      });
      return;
    }
    setState(() {
      for (final row in _controllers) {
        row.removeAt(col).dispose();
      }
      for (final f in _focusNodes) {
        f.dispose();
      }
      _focusNodes.clear();
    });
    _emit();
    final nextCol = col.clamp(0, _columnCount - 1);
    runAfterKeystroke(() {
      if (!mounted) return;
      _focusCell(focusRow.clamp(0, _controllers.length - 1), nextCol);
    });
  }

  void _addColumnOrCap(int col, {required int focusRow}) {
    if (_columnCount >= _maxColumns) return;
    _addColumnAfter(col, focusRow: focusRow);
  }

  /// Enter / Tab move cells; arrows use [FormattedTextField] edge exits (2D grid).
  KeyEventResult _onKey(FocusNode node, KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onFocus?.call();
      if (_isChart) {
        if (_columnIsEmpty(col)) {
          widget.onExitTable?.call(col);
          return KeyEventResult.handled;
        }
        if (col + 1 < _columnCount) {
          _focusCell(row, col + 1);
        } else {
          _addColumnOrCap(col, focusRow: row);
        }
        return KeyEventResult.handled;
      }
      if (_rowIsEmpty(row)) {
        widget.onExitTable?.call(row);
        return KeyEventResult.handled;
      }
      if (row + 1 < _controllers.length) {
        _focusCell(row + 1, col);
      } else {
        _addRowAfter(row);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_isChart) {
        if (row == 0) {
          _focusCell(1, col);
        } else if (col + 1 < _columnCount) {
          _focusCell(0, col + 1);
        } else {
          _focusCell(0, 0);
        }
        return KeyEventResult.handled;
      }
      final nextCol = col + 1;
      if (nextCol < _controllers[row].length) {
        _focusCell(row, nextCol);
      } else if (row + 1 < _controllers.length) {
        _focusCell(row + 1, 0);
      }
      return KeyEventResult.handled;
    }

    if (_isChart && event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = _controllers[row][col];
      final sel = controller.selection;
      final atStart = !sel.isValid || (sel.isCollapsed && sel.baseOffset <= 0);
      if (atStart && controller.text.isEmpty && _columnIsEmpty(col)) {
        _removeColumnAt(col, focusRow: row);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _showMenu(TapDownDetails details, int row, int col) async {
    await DocumentContextMenu.showTableCellMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.strings,
      extraEntries: widget.extraMenuEntries,
      onAction: (action) async {
        if (action == 'table:add_column') {
          _addColumnOrCap(col, focusRow: row);
          return;
        }
        final extra = widget.onExtraMenuAction;
        if (extra != null &&
            (action.startsWith('chart:') ||
                widget.extraMenuEntries.isNotEmpty)) {
          // Let the host claim chart:* (and any other extras) first.
          if (action.startsWith('chart:')) {
            await extra(action);
            return;
          }
        }
        await runBlockTextAction(action);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Color.alphaBlend(
      scheme.outline.withValues(alpha: 0.55),
      scheme.surface,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < _controllers.length; r++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < _controllers[r].length; c++) ...[
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
                            bottom: r < _controllers.length - 1
                                ? BorderSide(color: borderColor, width: 1)
                                : BorderSide.none,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: _minCellHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                              child: Focus(
                              // Ancestor-only node (Enter/Tab). Cell focus stays
                              // on FormattedTextField's node — do not share it.
                              onKeyEvent: (node, event) =>
                                  _onKey(node, event, r, c),
                              child: FormattedTextField(
                                controller: _controllers[r][c],
                                focusNode: _focusAt(r, c),
                                segmentId: tableCellSegmentId(widget.node.id, r, c),
                                documentBaseOffset: widget.documentBaseOffset,
                                style: AppTypography.documentParagraphStyle,
                                hintText: r == 0 && c == 0
                                    ? (widget.cellHint ?? 'Cell')
                                    : null,
                                maxLines: null,
                                minLines: 1,
                                onChanged: (_) => _emit(),
                                onBackspaceAtStart: () async {
                                  if (_isChart) {
                                    if (_controllers[r][c].text.isEmpty &&
                                        _columnIsEmpty(c)) {
                                      _removeColumnAt(c, focusRow: r);
                                    }
                                    return;
                                  }
                                  if (_controllers[r][c].text.isEmpty &&
                                      _rowIsEmpty(r)) {
                                    _removeRowAt(r);
                                  }
                                },
                                onSecondaryTapDown: (d) => _showMenu(d, r, c),
                                onArrowExitAbove: () =>
                                    _arrowVertical(r, c, goingDown: false),
                                onArrowExitBelow: () =>
                                    _arrowVertical(r, c, goingDown: true),
                                onArrowExitLeft: () =>
                                    _arrowHorizontal(r, c, goingRight: false),
                                onArrowExitRight: () =>
                                    _arrowHorizontal(r, c, goingRight: true),
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
    );
  }
}
