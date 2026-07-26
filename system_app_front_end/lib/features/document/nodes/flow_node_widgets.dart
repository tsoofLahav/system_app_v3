import 'package:flutter/material.dart';

import '../../../design_system/app_colors.dart';
import '../../../design_system/app_typography.dart';
import '../document_model.dart';

class TableNodeWidget extends StatefulWidget {
  const TableNodeWidget({
    super.key,
    required this.node,
    required this.onChanged,
  });

  final TableNode node;
  final ValueChanged<TableNode> onChanged;

  @override
  State<TableNodeWidget> createState() => _TableNodeWidgetState();
}

class _TableNodeWidgetState extends State<TableNodeWidget> {
  late List<List<String>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.node.rows.map((r) => List<String>.from(r)).toList();
    if (_rows.isEmpty) _rows = [['', '']];
  }

  void _commit() {
    widget.onChanged(TableNode(id: widget.node.id, rows: _rows));
  }

  void _setCell(int row, int col, String value) {
    setState(() {
      _rows[row][col] = value;
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final colCount = _rows.map((r) => r.length).fold(2, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: AppColors.noteBorder),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var ri = 0; ri < _rows.length; ri++)
              TableRow(
                children: [
                  for (var ci = 0; ci < colCount; ci++)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 120,
                        child: TextField(
                          controller: TextEditingController(
                            text: ci < _rows[ri].length ? _rows[ri][ci] : '',
                          ),
                          style: AppTypography.noteBodyStyle,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onChanged: (v) => _setCell(ri, ci, v),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ListNodeWidget extends StatelessWidget {
  const ListNodeWidget({
    super.key,
    required this.node,
    required this.onChanged,
  });

  final ListNode node;
  final ValueChanged<ListNode> onChanged;

  @override
  Widget build(BuildContext context) {
    final numbered = node.listStyle == 'numbered';
    final items = node.items.isEmpty ? [''] : node.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  numbered ? '${i + 1}.' : '•',
                  style: AppTypography.listItemStyle,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: items[i]),
                  style: AppTypography.listItemStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  onChanged: (value) {
                    final next = List<String>.from(items);
                    next[i] = value;
                    onChanged(ListNode(
                      id: node.id,
                      items: next,
                      listStyle: node.listStyle,
                    ));
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class ImageNodeWidget extends StatefulWidget {
  const ImageNodeWidget({
    super.key,
    required this.node,
    required this.onChanged,
  });

  final ImageNode node;
  final ValueChanged<ImageNode> onChanged;

  @override
  State<ImageNodeWidget> createState() => _ImageNodeWidgetState();
}

class _ImageNodeWidgetState extends State<ImageNodeWidget> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.node.url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.node.url.isNotEmpty)
            Image.network(
              widget.node.url,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 80,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'Image URL',
              isDense: true,
            ),
            onSubmitted: (url) => widget.onChanged(
              ImageNode(id: widget.node.id, url: url, width: widget.node.width),
            ),
          ),
        ],
      ),
    );
  }
}

class GraphNodeWidget extends StatefulWidget {
  const GraphNodeWidget({
    super.key,
    required this.node,
    required this.onChanged,
  });

  final GraphNode node;
  final ValueChanged<GraphNode> onChanged;

  @override
  State<GraphNodeWidget> createState() => _GraphNodeWidgetState();
}

class _GraphNodeWidgetState extends State<GraphNodeWidget> {
  late List<String> _labels;
  late List<double> _values;

  @override
  void initState() {
    super.initState();
    _labels = List<String>.from(widget.node.labels);
    _values = List<double>.from(widget.node.values);
    if (_labels.isEmpty) {
      _labels = ['A'];
      _values = [1];
    }
  }

  void _commit() {
    widget.onChanged(GraphNode(id: widget.node.id, labels: _labels, values: _values));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _SimpleBarPainter(_values),
              child: Container(),
            ),
          ),
          for (var i = 0; i < _labels.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _labels[i]),
                    decoration: InputDecoration(hintText: 'Label ${i + 1}'),
                    onChanged: (v) {
                      _labels[i] = v;
                      _commit();
                    },
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: TextEditingController(
                      text: i < _values.length ? _values[i].toString() : '0',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      _values[i] = double.tryParse(v) ?? 0;
                      _commit();
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SimpleBarPainter extends CustomPainter {
  _SimpleBarPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final barWidth = size.width / values.length;
    final paint = Paint()..color = AppColors.primary;
    for (var i = 0; i < values.length; i++) {
      final h = maxVal == 0 ? 0.0 : (values[i] / maxVal) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth + 4, size.height - h, barWidth - 8, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleBarPainter oldDelegate) =>
      oldDelegate.values != values;
}
