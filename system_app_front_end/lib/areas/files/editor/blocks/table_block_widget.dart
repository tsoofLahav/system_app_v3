import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_typography.dart';
import '../../model/document_model.dart';

class DocumentTableBlockWidget extends StatefulWidget {
  const DocumentTableBlockWidget({
    super.key,
    required this.node,
    required this.onChanged,
  });

  final TableNode node;
  final ValueChanged<TableNode> onChanged;

  @override
  State<DocumentTableBlockWidget> createState() => _DocumentTableBlockWidgetState();
}

class _DocumentTableBlockWidgetState extends State<DocumentTableBlockWidget> {
  late List<List<TextEditingController>> _controllers;
  final _focusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(DocumentTableBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _disposeControllers();
      _syncControllers();
    }
  }

  void _syncControllers() {
    _controllers = [
      for (final row in widget.node.rows)
        [for (final cell in row) TextEditingController(text: cell.text)],
    ];
  }

  void _disposeControllers() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.node.copyWith(
        rows: [
          for (var r = 0; r < _controllers.length; r++)
            [
              for (var c = 0; c < _controllers[r].length; c++)
                DocumentTableCell(text: _controllers[r][c].text, spans: widget.node.rows[r][c].spans),
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final nextCol = col + 1;
      if (nextCol < _controllers[row].length) {
        _focusAt(row, nextCol).requestFocus();
      } else if (row + 1 < _controllers.length) {
        _focusAt(row + 1, 0).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && row + 1 < _controllers.length) {
      _focusAt(row + 1, col).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && row > 0) {
      _focusAt(row - 1, col).requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < _controllers.length; r++)
          Row(
            children: [
              for (var c = 0; c < _controllers[r].length; c++)
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) => _onKey(node, event, r, c),
                    child: TextField(
                      controller: _controllers[r][c],
                      focusNode: _focusAt(r, c),
                      style: AppTypography.noteBodyStyle,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(6),
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                ),
            ],
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _controllers.add([
                for (var i = 0; i < _controllers.first.length; i++)
                  TextEditingController(),
              ]);
            });
            _emit();
          },
          child: const Text('Add row'),
        ),
      ],
    );
  }
}
