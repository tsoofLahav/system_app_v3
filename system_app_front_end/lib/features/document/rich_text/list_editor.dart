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
  /// Called when the user exits the list (empty item + Enter). Passes the empty item index.
  final ValueChanged<int> onExitList;
  final VoidCallback? onFocus;

  @override
  State<RichListEditor> createState() => _RichListEditorState();
}

class _RichListEditorState extends State<RichListEditor> {
  final _controllers = <SpanTextEditingController>[];
  final _focusNodes = <FocusNode>[];
  int? _pendingFocusIndex;

  @override
  void initState() {
    super.initState();
    _syncFromNode();
  }

  bool _localStateMatchesNode() {
    if (_controllers.length != widget.node.items.length) return false;
    for (var i = 0; i < _controllers.length; i++) {
      if (_controllers[i].text != widget.node.items[i].text) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(RichListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _disposeControllers();
      _syncFromNode();
      return;
    }
    if (_localStateMatchesNode()) return;
    final focusIdx = _pendingFocusIndex ?? _focusNodes.indexWhere((f) => f.hasFocus);
    _disposeControllers();
    _syncFromNode();
    if (focusIdx >= 0 && focusIdx < _focusNodes.length) {
      _pendingFocusIndex = focusIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());
    }
  }

  void _applyPendingFocus() {
    if (!mounted) return;
    final idx = _pendingFocusIndex;
    if (idx == null || idx < 0 || idx >= _focusNodes.length) return;
    _pendingFocusIndex = null;
    _focusNodes[idx].requestFocus();
    final controller = _controllers[idx];
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
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
    final newIndex = index + 1;
    setState(() {
      _controllers.insert(newIndex, SpanTextEditingController(text: ''));
      _focusNodes.insert(newIndex, FocusNode());
    });
    _emit();
    _pendingFocusIndex = newIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFocus());
  }

  void _removeItemAt(int index) {
    if (_controllers.length <= 1) {
      widget.onExitList(index);
      return;
    }
    final removedFocus = _focusNodes[index];
    setState(() {
      _controllers.removeAt(index).dispose();
      _focusNodes.removeAt(index);
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removedFocus.dispose();
      if (!mounted) return;
      final focusPrev = index > 0 ? index - 1 : 0;
      if (focusPrev < _focusNodes.length) {
        _focusNodes[focusPrev].requestFocus();
      }
    });
  }

  void _handleEnter(int index) {
    widget.onFocus?.call();
    final text = _controllers[index].text;
    if (text.trim().isEmpty) {
      widget.onExitList(index);
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
