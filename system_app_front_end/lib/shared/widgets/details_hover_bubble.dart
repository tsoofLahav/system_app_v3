import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';

class DetailsHoverBubble extends StatelessWidget {
  const DetailsHoverBubble({
    super.key,
    required this.block,
    this.maxHeight = 240,
    this.maxWidth = 320,
  });

  final Block block;
  final double maxHeight;
  final double maxWidth;

  static const _radius = 10.0;
  static const _minWidth = 120.0;
  static const _horizontalPadding = 24.0;

  static List<BoxShadow> get _shadows => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  double _bubbleWidth(BuildContext context, String title, String body) {
    final direction = Directionality.of(context);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );
    final innerMax = maxWidth - _horizontalPadding;

    double measure(String text, TextStyle style, {bool wrap = false}) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: wrap ? null : 1,
      )..layout(maxWidth: innerMax);
      return painter.size.width;
    }

    final contentWidth = math.max(
      measure(title, titleStyle),
      measure(body, bodyStyle, wrap: true),
    );
    if (contentWidth <= 0) return _minWidth;
    return (contentWidth + _horizontalPadding).clamp(_minWidth, maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final content = block.content;
    final title = content['title']?.toString().trim() ?? '';
    final body = content['text']?.toString().trim() ?? '';
    if (title.isEmpty && body.isEmpty) {
      return const SizedBox.shrink();
    }

    final width = _bubbleWidth(context, title, body);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );
    final bodyMaxHeight = math.max(48.0, maxHeight - 56);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: _shadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.68),
                  width: 0.85,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(title, style: titleStyle),
                    ),
                  if (body.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                      child: SingleChildScrollView(
                        child: Text(body, style: bodyStyle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailsHoverTarget extends StatefulWidget {
  const DetailsHoverTarget({
    super.key,
    required this.child,
    required this.detailsBlockId,
    required this.loadBlock,
  });

  final Widget child;
  final int? detailsBlockId;
  final Future<Block?> Function(int blockId) loadBlock;

  @override
  State<DetailsHoverTarget> createState() => _DetailsHoverTargetState();
}

class _DetailsHoverTargetState extends State<DetailsHoverTarget> {
  OverlayEntry? _entry;
  Block? _block;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _showOverlay() async {
    final blockId = widget.detailsBlockId;
    if (blockId == null || _entry != null) return;
    _block ??= await widget.loadBlock(blockId);
    if (!mounted || _block == null) return;

    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: origin.dx,
        top: origin.dy + box.size.height + 6,
        child: DetailsHoverBubble(block: _block!),
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.detailsBlockId == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => _showOverlay(),
      onExit: (_) => _removeOverlay(),
      child: widget.child,
    );
  }
}
