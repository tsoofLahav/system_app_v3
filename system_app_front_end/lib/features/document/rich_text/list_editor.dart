import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../design_system/app_typography.dart';
import '../document_codec.dart';
import '../document_model.dart';
import 'block_text_actions.dart';
import 'document_context_menu.dart';
import 'formatted_text_field.dart';
import 'span_text_editing_controller.dart';

class RichListEditor extends StatefulWidget {
  const RichListEditor({
    super.key,
    required this.node,
    required this.strings,
    required this.onChanged,
    required this.onExitList,
    this.onFocus,
  });

  final ListNode node;
  final AppStrings strings;
  final ValueChanged<ListNode> onChanged;
  final VoidCallback onExitList;
  final VoidCallback? onFocus;

  @override
  State<RichListEditor> createState() => _RichListEditorState();
}

class _RichListEditorState extends State<RichListEditor> {
  final _controllers = <SpanTextEditingController>[];
  final _focusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncFromNode();
  }

  @override
  void didUpdateWidget(RichListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.node.items.length != widget.node.items.length) {
      _disposeControllers();
      _syncFromNode();
    }
  }

  void _syncFromNode() {
    for (final item in widget.node.items) {
      _controllers.add(
        SpanTextEditingController(
          text: item.text,
          spans: item.spans.map((s) => s.toJson()).toList(),
        ),
      );
      _focusNodes.add(FocusNode());
    }
    if (_controllers.isEmpty) {
      _controllers.add(SpanTextEditingController(text: ''));
      _focusNodes.add(FocusNode());
    }
  }

  void _disposeControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers.clear();
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
        items: [
          for (var i = 0; i < _controllers.length; i++)
            ListItem(
              id: i < widget.node.items.length
                  ? widget.node.items[i].id
                  : DocumentCodec.newId('li'),
              text: _controllers[i].text,
              indent: i < widget.node.items.length ? widget.node.items[i].indent : 0,
              spans: [
                for (final s in _controllers[i].spans)
                  TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
              ],
            ),
        ],
      ),
    );
  }

  void _insertItemAfter(int index) {
    setState(() {
      _controllers.insert(index + 1, SpanTextEditingController(text: ''));
      _focusNodes.insert(index + 1, FocusNode());
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index + 1 < _focusNodes.length) {
        _focusNodes[index + 1].requestFocus();
      }
    });
  }

  void _removeItemAt(int index) {
    if (_controllers.length <= 1) {
      widget.onExitList();
      return;
    }
    setState(() {
      _controllers.removeAt(index).dispose();
      final node = _focusNodes.removeAt(index);
      final focusPrev = index > 0 ? index - 1 : 0;
      node.dispose();
      _emit();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusPrev < _focusNodes.length) {
          _focusNodes[focusPrev].requestFocus();
        }
      });
    });
  }

  void _handleEnter(int index) {
    widget.onFocus?.call();
    final text = _controllers[index].text;
    if (text.trim().isEmpty) {
      widget.onExitList();
      return;
    }
    _insertItemAfter(index);
  }

  Future<void> _handleBackspace(int index) async {
    widget.onFocus?.call();
    if (_controllers[index].text.isEmpty) {
      _removeItemAt(index);
    }
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
    final ordered = widget.node.isOrdered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    ordered ? '${i + 1}.' : '•',
                    style: AppTypography.listItemStyle,
                  ),
                ),
                Expanded(
                  child: FormattedTextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    style: AppTypography.listItemStyle,
                    maxLines: null,
                    minLines: 1,
                    onChanged: (_) => _emit(),
                    onEnter: () => _handleEnter(i),
                    onBackspaceAtStart: () => _handleBackspace(i),
                    onSecondaryTapDown: _showMenu,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
