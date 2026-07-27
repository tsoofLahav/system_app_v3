import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_typography.dart';
import '../editor/document_text_flow.dart';
import '../model/document_model.dart';
import './block_text_actions.dart';
import './document_context_menu.dart';
import './formatted_text_field.dart';
import './span_text_editing_controller.dart';

class RichTableEditor extends StatefulWidget {
  const RichTableEditor({
    super.key,
    required this.node,
    required this.strings,
    required this.onChanged,
    this.onFocus,
    this.onExitTable,
  });

  final TableNode node;
  final AppStrings strings;
  final ValueChanged<TableNode> onChanged;
  final VoidCallback? onFocus;
  final ValueChanged<int>? onExitTable;

  @override
  State<RichTableEditor> createState() => _RichTableEditorState();
}

class _RichTableEditorState extends State<RichTableEditor> {
  late List<List<SpanTextEditingController>> _controllers;
  final _focusNodes = <FocusNode>[];

  static const _defaultColumns = 2;
  static const _minCellHeight = 36.0;

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

  List<List<DocumentTableCell>> get _normalizedRows {
    if (widget.node.rows.isEmpty) {
      return [
        for (var r = 0; r < 1; r++)
          [
            for (var c = 0; c < _defaultColumns; c++)
              const DocumentTableCell(text: ''),
          ],
      ];
    }
    final maxCols = widget.node.rows
        .map((row) => row.length)
        .fold(_defaultColumns, (a, b) => a > b ? a : b);
    final targetCols = maxCols < _defaultColumns ? _defaultColumns : maxCols;
    return [
      for (final row in widget.node.rows)
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

  void _focusCell(int row, int col) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAt(row, col).requestFocus();
    });
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
    });
    _emit();
    _focusCell(row + 1, 0);
  }

  void _addColumnAfter(int col, {required int focusRow}) {
    setState(() {
      for (final row in _controllers) {
        row.insert(col + 1, SpanTextEditingController(text: ''));
      }
    });
    _emit();
    _focusCell(focusRow, col + 1);
  }

  bool _rowIsEmpty(int row) {
    return _controllers[row].every((c) => c.text.trim().isEmpty);
  }

  /// Enter and Tab only. Arrow keys belong to the document text flow, which
  /// moves by column inside the table and out of it at the edge rows.
  KeyEventResult _onKey(FocusNode node, KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onFocus?.call();
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
      final nextCol = col + 1;
      if (nextCol < _controllers[row].length) {
        _focusCell(row, nextCol);
      } else if (row + 1 < _controllers.length) {
        _focusCell(row + 1, 0);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _showMenu(TapDownDetails details, int row, int col) async {
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
                              onKeyEvent: (node, event) => _onKey(node, event, r, c),
                              child: FormattedTextField(
                                controller: _controllers[r][c],
                                focusNode: _focusAt(r, c),
                                segmentId: tableCellSegmentId(widget.node.id, r, c),
                                style: AppTypography.noteBodyStyle,
                                hintText: r == 0 && c == 0 ? 'Cell' : null,
                                maxLines: null,
                                minLines: 1,
                                onChanged: (_) => _emit(),
                                onSecondaryTapDown: (d) => _showMenu(d, r, c),
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
