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
import './rtl/rtl.dart';
import './span_text_editing_controller.dart';
import './table_reorder_surface.dart';

/// Grid editing modes for [RichTableEditor].
enum TableEditorMode {
  /// Arbitrary rows × columns; Enter grows rows.
  grid,

  /// Fixed 2 rows (labels/values); Enter grows columns (series), capped.
  chartSeries,
}

/// Editable N×M (or chart 2×N) cell grid.
///
/// Product rules: files [`AREA.md` § Tables & charts](../AREA.md#tables--charts).
/// Reorder UI: [TableReorderSurface].
///
/// File layout: lifecycle/sync → focus & arrows → insert/remove → keys & menu
/// → permute → build.
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
    this.onReorderColumn,
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

  /// Chart host: permute series colors when a column is dragged.
  final void Function(int from, int to)? onReorderColumn;

  @override
  State<RichTableEditor> createState() => RichTableEditorState();
}

class RichTableEditorState extends State<RichTableEditor> {
  late List<List<SpanTextEditingController>> _controllers;

  /// One [FocusNode] per cell — shape matches [_controllers].
  var _focusGrid = <List<FocusNode>>[];

  /// Last cell that held focus or was right-clicked (add row/column anchor).
  (int, int)? _lastCell;

  TableReorderKind? _reorderKind;

  static const _defaultColumns = 2;
  static const _minCellHeight = 36.0;

  /// True while a cell owns focus (used by [TableEmbed] to keep local SoT).
  bool get hasInnerFocus =>
      _focusGrid.any((row) => row.any((f) => f.hasFocus));

  bool get reorderMode => _reorderKind != null;

  void beginReorderRows() => _enterReorder(TableReorderKind.rows);

  void beginReorderColumns() => _enterReorder(TableReorderKind.columns);

  void _enterReorder(TableReorderKind kind) {
    if (_reorderKind == kind) return;
    setState(() => _reorderKind = kind);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _exitReorder() {
    if (_reorderKind == null) return;
    setState(() => _reorderKind = null);
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
    _ensureFocusGrid();
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
      _ensureFocusGrid();
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
    final resume = _lastCell;
    _disposeAll();
    _syncControllers();
    _ensureFocusGrid();
    if (resume != null) {
      final (row, col) = resume;
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

  int get _columnCount =>
      _controllers.isEmpty ? _defaultColumns : _controllers.first.length;

  void _unfocusAllCells() {
    for (final row in _focusGrid) {
      for (final n in row) {
        if (n.hasFocus) n.unfocus();
      }
    }
  }

  void _disposeFocusGrid() {
    _unfocusAllCells();
    for (final row in _focusGrid) {
      for (final n in row) {
        n.dispose();
      }
    }
    _focusGrid = [];
  }

  /// Keep [_focusGrid] aligned with [_controllers] (create/dispose as needed).
  void _ensureFocusGrid() {
    final rows = _controllers.length;
    final cols = _columnCount;

    // Shrink rows.
    while (_focusGrid.length > rows) {
      for (final n in _focusGrid.removeLast()) {
        if (n.hasFocus) n.unfocus();
        n.dispose();
      }
    }
    // Grow / adjust each row.
    for (var r = 0; r < rows; r++) {
      if (r >= _focusGrid.length) {
        _focusGrid.add([for (var c = 0; c < cols; c++) FocusNode()]);
        continue;
      }
      final row = _focusGrid[r];
      while (row.length > cols) {
        final n = row.removeLast();
        if (n.hasFocus) n.unfocus();
        n.dispose();
      }
      while (row.length < cols) {
        row.add(FocusNode());
      }
    }
  }

  void _disposeAll() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    _disposeFocusGrid();
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

  // --- Focus & 2D arrows -------------------------------------------------

  FocusNode _focusAt(int row, int col) {
    _ensureFocusGrid();
    return _focusGrid[row][col];
  }

  (int, int)? _focusedCell() {
    for (var r = 0; r < _focusGrid.length; r++) {
      for (var c = 0; c < _focusGrid[r].length; c++) {
        if (_focusGrid[r][c].hasFocus) return (r, c);
      }
    }
    return _lastCell;
  }

  int get lineCount => _controllers.length * _columnCount;

  void focusLine(int index, {required bool fromAbove}) {
    if (lineCount <= 0) return;
    final cols = _columnCount;
    final i = index.clamp(0, lineCount - 1);
    final row = i ~/ cols;
    final col = i % cols;
    _focusCell(row, col, atStart: fromAbove);
  }

  /// [Row] follows ambient [Directionality] — in Hebrew, col 0 is on the right.
  bool get _gridRtl => Directionality.of(context) == TextDirection.rtl;

  /// Physical grid: ↓/↑ stay in the same column; ←/→ stay in the same row.
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
    widget.onExitTable?.call(-1);
  }

  /// [goingRight] is the physical/visual key (←/→), matching in-cell RTL motion.
  /// In an RTL grid, visual right is toward lower column indices.
  void _arrowHorizontal(int row, int col, {required bool goingRight}) {
    final towardHigherCol = _gridRtl ? !goingRight : goingRight;
    if (towardHigherCol) {
      if (col + 1 < _columnCount) {
        // Land on the edge we entered from (visual left in RTL = logical end).
        _focusCell(row, col + 1, atStart: !_gridRtl);
      }
      return;
    }
    if (col > 0) {
      _focusCell(row, col - 1, atStart: _gridRtl);
    }
  }

  void _focusCell(int row, int col, {bool atStart = true}) {
    if (row < 0 ||
        col < 0 ||
        row >= _controllers.length ||
        col >= _controllers[row].length) {
      return;
    }
    final target = _focusAt(row, col);
    // One caret only — drop every other cell before claiming focus.
    for (final focusRow in _focusGrid) {
      for (final n in focusRow) {
        if (!identical(n, target) && n.hasFocus) n.unfocus();
      }
    }
    final controller = _controllers[row][col];
    final len = controller.text.length;
    controller.selection = TextSelection.collapsed(
      offset: atStart ? 0 : len,
    );
    _lastCell = (row, col);
    target.requestFocus();
  }

  void _rebuildFocusGrid() {
    _disposeFocusGrid();
    _ensureFocusGrid();
  }

  // --- Insert / remove ---------------------------------------------------

  void _addRowAfter(int row) {
    setState(() {
      _unfocusAllCells();
      _controllers.insert(
        row + 1,
        [
          for (var i = 0; i < _columnCount; i++)
            SpanTextEditingController(text: ''),
        ],
      );
      _rebuildFocusGrid();
    });
    _emit();
    runNextFrame(() {
      if (!mounted) return;
      _focusCell(row + 1, 0);
    });
  }

  /// Insert immediately after [col] in reading/storage order (index [col]+1).
  ///
  /// In an RTL grid that is also visually to the left of [col]. The anchor is
  /// always the right-clicked / focused cell — never a drifting “end” column.
  void _addColumnAfter(int col, {required int focusRow}) {
    final anchorCol = col.clamp(0, _columnCount - 1);
    final nextCol = anchorCol + 1;
    _lastCell = (focusRow, anchorCol);
    setState(() {
      // Unfocus first; surgically insert nodes — full grid dispose mid-handoff
      // leaves ghost carets (especially chart tables that parent-rebuild).
      _unfocusAllCells();
      _ensureFocusGrid();
      for (var r = 0; r < _controllers.length; r++) {
        _controllers[r].insert(nextCol, SpanTextEditingController(text: ''));
        _focusGrid[r].insert(nextCol, FocusNode());
      }
    });
    _emit();
    // Two frames: parent chart setState (deferred) must finish before focus.
    // Land in the new column so the user can type; next Add uses that cell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _unfocusAllCells();
        _focusCell(
          focusRow.clamp(0, _controllers.length - 1),
          nextCol.clamp(0, _columnCount - 1),
        );
      });
    });
  }

  /// Insert a column after the focused/last-clicked cell.
  void addColumnAfterCurrent() {
    if (_columnCount >= _maxColumns) return;
    final cell = _focusedCell();
    final row = (cell?.$1 ?? 0).clamp(0, _controllers.length - 1);
    final col = (cell?.$2 ?? (_columnCount - 1)).clamp(0, _columnCount - 1);
    _addColumnOrCap(col, focusRow: row);
  }

  /// Insert a row after the focused/last-clicked cell (plain tables only).
  void addRowAfterCurrent() {
    if (_isChart || _controllers.isEmpty) return;
    final cell = _focusedCell();
    final row = (cell?.$1 ?? (_controllers.length - 1))
        .clamp(0, _controllers.length - 1);
    _addRowAfter(row);
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

  void _removeRowAt(int row) {
    widget.onFocus?.call();
    if (row < 0 || row >= _controllers.length) return;
    if (!_rowIsEmpty(row)) return;
    if (_controllers.length <= 1) {
      (widget.onDeleteTable ?? () => widget.onExitTable?.call(row))();
      return;
    }
    setState(() {
      _unfocusAllCells();
      for (final c in _controllers.removeAt(row)) {
        c.dispose();
      }
      _rebuildFocusGrid();
    });
    _emit();
    final focusRow = (row > 0 ? row - 1 : 0).clamp(0, _controllers.length - 1);
    runNextFrame(() {
      if (!mounted) return;
      _focusCell(focusRow, 0);
    });
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
      _unfocusAllCells();
      _ensureFocusGrid();
      for (var r = 0; r < _controllers.length; r++) {
        _controllers[r].removeAt(col).dispose();
        if (r < _focusGrid.length && col < _focusGrid[r].length) {
          _focusGrid[r].removeAt(col).dispose();
        }
      }
    });
    _emit();
    final nextCol = col.clamp(0, _columnCount - 1);
    runAfterKeystroke(() {
      if (!mounted) return;
      _unfocusAllCells();
      _focusCell(focusRow.clamp(0, _controllers.length - 1), nextCol);
    });
  }

  void _addColumnOrCap(int col, {required int focusRow}) {
    if (_columnCount >= _maxColumns) return;
    _addColumnAfter(col, focusRow: focusRow);
  }

  // --- Keys & cell menu --------------------------------------------------

  bool _atVisualHorizontalEdge(
    TextEditingController controller, {
    required bool goingLeft,
  }) {
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    final caret = selection.extentOffset;
    final textLen = controller.text.length;
    final rtl = resolveFieldTextDirection(
          controller.text,
          Directionality.of(context),
        ) ==
        TextDirection.rtl;
    if (goingLeft) return rtl ? caret >= textLen : caret <= 0;
    return rtl ? caret <= 0 : caret >= textLen;
  }

  /// Own Enter/Tab/←/→ like Enter: edge → other cell; else defer to text/RTL.
  KeyEventResult _onCellKey(FocusNode node, KeyEvent event, int row, int col) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDownArrow = key == LogicalKeyboardKey.arrowDown;

    if (isLeft || isRight || isUp || isDownArrow) {
      if (HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed) {
        return KeyEventResult.ignored;
      }
      if (isLeft || isRight) {
        final goingLeft = isLeft;
        if (!_atVisualHorizontalEdge(
          _controllers[row][col],
          goingLeft: goingLeft,
        )) {
          // Not at edge — TextField + RTL flip move inside the cell.
          return KeyEventResult.ignored;
        }
        _arrowHorizontal(row, col, goingRight: !goingLeft);
        return KeyEventResult.handled;
      }
      // ↑/↓ edge exits stay on FormattedTextField (first/last visual line).
      return KeyEventResult.ignored;
    }

    if (!isDown) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.enter &&
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

    if (key == LogicalKeyboardKey.tab) {
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

    if (_isChart && key == LogicalKeyboardKey.backspace) {
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
    // Anchor insert-after to the cell under the pointer — not whichever cell
    // still happens to own focus.
    _lastCell = (row, col);
    final anchorRow = row;
    final anchorCol = col;
    await DocumentContextMenu.showTableCellMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.strings,
      includeAddRow: !_isChart,
      includeReorderRows: !_isChart,
      includeReorderColumns: true,
      extraEntries: widget.extraMenuEntries,
      onAction: (action) async {
        if (action == 'table:add_column') {
          _addColumnOrCap(anchorCol, focusRow: anchorRow);
          return;
        }
        if (action == 'table:add_row') {
          if (!_isChart) _addRowAfter(anchorRow);
          return;
        }
        if (action == 'table:reorder_rows') {
          beginReorderRows();
          return;
        }
        if (action == 'table:reorder_columns') {
          beginReorderColumns();
          return;
        }
        final extra = widget.onExtraMenuAction;
        if (extra != null &&
            (action.startsWith('chart:') ||
                widget.extraMenuEntries.isNotEmpty)) {
          if (action.startsWith('chart:')) {
            await extra(action);
            return;
          }
        }
        await runBlockTextAction(action);
      },
    );
  }

  // --- Reorder permute (UI in TableReorderSurface) -----------------------

  void _moveRow(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    if (from >= _controllers.length || to >= _controllers.length) return;
    setState(() {
      final rowCtrls = _controllers.removeAt(from);
      _controllers.insert(to, rowCtrls);
      final rowFocus = _focusGrid.removeAt(from);
      _focusGrid.insert(to, rowFocus);
    });
    _emit();
  }

  void _moveColumn(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    final cols = _controllers.isEmpty ? 0 : _controllers.first.length;
    if (from >= cols || to >= cols) return;
    setState(() {
      for (final row in _controllers) {
        final cell = row.removeAt(from);
        row.insert(to, cell);
      }
      for (final row in _focusGrid) {
        final focus = row.removeAt(from);
        row.insert(to, focus);
      }
    });
    widget.onReorderColumn?.call(from, to);
    _emit();
  }

  List<List<String>> get _cellTexts => [
        for (final row in _controllers)
          [for (final cell in row) cell.text],
      ];

  @override
  Widget build(BuildContext context) {
    _ensureFocusGrid();
    final kind = _reorderKind;
    if (kind != null) {
      return TableReorderSurface(
        kind: kind,
        cells: _cellTexts,
        strings: widget.strings,
        onMoveRow: _moveRow,
        onMoveColumn: _moveColumn,
        onDone: _exitReorder,
      );
    }
    return _buildEditGrid(context);
  }

  Widget _buildEditGrid(BuildContext context) {
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
                          constraints:
                              const BoxConstraints(minHeight: _minCellHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: FormattedTextField(
                              controller: _controllers[r][c],
                              focusNode: _focusAt(r, c),
                              hostKeyEvent: (node, event) =>
                                  _onCellKey(node, event, r, c),
                              segmentId:
                                  tableCellSegmentId(widget.node.id, r, c),
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
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
