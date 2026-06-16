import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';

class PointsListBlockWidget extends StatefulWidget {
  const PointsListBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<PointsListBlockWidget> createState() => _PointsListBlockWidgetState();
}

class _PointsListBlockWidgetState extends State<PointsListBlockWidget> {
  final _focusNodes = <FocusNode>[];
  int? _pendingFocusIndex;

  @override
  void didUpdateWidget(PointsListBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requestPendingFocus();
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFrom(widget.block.content['items']);
    _syncFocusNodes(items.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                child: Text(
                  '•',
                  textAlign: TextAlign.center,
                  style: AppTypography.noteBodyStyle,
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('${widget.block.id}-$i'),
                  focusNode: _focusNodes[i],
                  initialValue: items[i],
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.noteBodyStyle,
                  decoration: AppTypography.noteInputDecoration(),
                  onChanged: (value) {
                    final next = [...items];
                    next[i] = value;
                    widget.onChanged({
                      ...widget.block.content,
                      'items': _toContentItems(next),
                    });
                  },
                  onFieldSubmitted: (_) {
                    _pendingFocusIndex = i + 1;
                    final next = [...items]..insert(i + 1, '');
                    widget.onChanged({
                      ...widget.block.content,
                      'items': _toContentItems(next),
                    });
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _syncFocusNodes(int count) {
    while (_focusNodes.length < count) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
  }

  void _requestPendingFocus() {
    final index = _pendingFocusIndex;
    if (index == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _focusNodes.length) return;
      _focusNodes[index].requestFocus();
    });
    _pendingFocusIndex = null;
  }

  static List<String> _itemsFrom(Object? value) {
    if (value is! List || value.isEmpty) return [''];
    return [
      for (final item in value)
        if (item is Map)
          item['text']?.toString() ?? ''
        else
          item?.toString() ?? '',
    ];
  }

  static List<Map<String, dynamic>> _toContentItems(List<String> items) => [
    for (final item in items) {'text': item},
  ];
}
