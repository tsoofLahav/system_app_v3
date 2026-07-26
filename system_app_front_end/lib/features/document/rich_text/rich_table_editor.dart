import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../design_system/app_typography.dart';
import '../document_model.dart';
import 'block_text_actions.dart';
import 'document_context_menu.dart';
import 'formatted_text_field.dart';
import 'span_text_editing_controller.dart';

class RichTableEditor extends StatefulWidget {
  const RichTableEditor({
    super.key,
    required this.node,
    required this.strings,
    required this.onChanged,
    this.onFocus,
  });

  final TableNode node;
  final AppStrings strings;
  final ValueChanged<TableNode> onChanged;
  final VoidCallback? onFocus;

  @override
  State<RichTableEditor> createState() => _RichTableEditorState();
}

class _RichTableEditorState extends State<RichTableEditor> {
  late List<List<SpanTextEditingController>> _controllers;
  final _focusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(RichTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _disposeAll();
      _syncControllers();
    }
  }

  void _syncControllers() {
    _controllers = [
      for (final row in widget.node.rows)
        [
          for (final cell in row)
            SpanTextEditingController(
              text: cell.text,
              spans: cell.spans.map((s) => s.toJson()).toList(),
            ),
        ],
    ];
  }

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
    final index = row * _controllers.first.length + col;
    while (_focusNodes.length <= index) {
      _focusNodes.add(FocusNode());
    }
    return _focusNodes[index];
  }

  void _focusCell(int row, int col) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusAt(row, col).requestFocus();
    });
  }

  void _addRowAfter(int row) {
    setState(() {
      _controllers.insert(
        row + 1,
        [
          for (var i = 0; i < _controllers.first.length; i++)
            SpanTextEditingController(text: ''),
        ],
      );
    });
    _emit();
    _focusCell(row + 1, 0);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onFocus?.call();
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

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        row + 1 < _controllers.length) {
      _focusCell(row + 1, col);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && row > 0) {
      _focusCell(row - 1, col);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _showMenu(TapDownDetails details) async {
    await DocumentContextMenu.showTextMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.strings,
      onAction: runBlockTextAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < _controllers.length; r++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < _controllers[r].length; c++)
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) => _onKey(node, event, r, c),
                    child: FormattedTextField(
                      controller: _controllers[r][c],
                      focusNode: _focusAt(r, c),
                      style: AppTypography.noteBodyStyle,
                      maxLines: null,
                      minLines: 1,
                      onChanged: (_) => _emit(),
                      onSecondaryTapDown: _showMenu,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
