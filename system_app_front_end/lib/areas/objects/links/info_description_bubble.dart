import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../data/inner_task_mark.dart';
import '../data/inner_tasks.dart';

/// Glass hover bubble for a description-linked info object.
///
/// Title and prose are read-only. Inner checklist lines can be marked done /
/// active when [onToggleInner] is set.
class InfoDescriptionBubble extends StatefulWidget {
  const InfoDescriptionBubble({
    super.key,
    required this.title,
    this.body = '',
    this.maxHeight = 240,
    this.maxWidth = 320,
    this.onToggleInner,
  });

  final String title;
  final String body;
  final double maxHeight;
  final double maxWidth;

  /// Toggle an inner checkbox at [markOffset] in [body]; return the next body.
  final Future<String?> Function(String body, int markOffset)? onToggleInner;

  @override
  State<InfoDescriptionBubble> createState() => _InfoDescriptionBubbleState();
}

class _InfoDescriptionBubbleState extends State<InfoDescriptionBubble> {
  static const _radius = 10.0;
  static const _minWidth = 120.0;
  static const _horizontalPadding = 24.0;

  late String _body;

  @override
  void initState() {
    super.initState();
    _body = widget.body;
  }

  @override
  void didUpdateWidget(InfoDescriptionBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _body = widget.body;
  }

  double _bubbleWidth(BuildContext context) {
    final direction = Directionality.of(context);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );
    final innerMax = widget.maxWidth - _horizontalPadding;

    double measure(String text, TextStyle style, {bool wrap = false}) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: wrap ? null : 1,
      )..layout(maxWidth: innerMax);
      return painter.size.width;
    }

    final checklist = parseInnerTaskLines(_body);
    final checklistWidth = checklist.isEmpty
        ? 0.0
        : checklist
            .map((item) => measure(item.title, bodyStyle) + 28)
            .fold<double>(0, math.max);

    final contentWidth = math.max(
      measure(widget.title, titleStyle),
      math.max(measure(_body, bodyStyle, wrap: true), checklistWidth),
    );
    if (contentWidth <= 0) return _minWidth;
    return (contentWidth + _horizontalPadding).clamp(_minWidth, widget.maxWidth);
  }

  Future<void> _toggle(InnerTaskLine item) async {
    final onToggle = widget.onToggleInner;
    if (onToggle == null) return;
    final next = await onToggle(_body, item.markStart);
    if (!mounted || next == null) return;
    setState(() => _body = next);
  }

  List<Widget> _bodyChildren(TextStyle bodyStyle) {
    final items = parseInnerTaskLines(_body);
    if (items.isEmpty) {
      return [Text(_body, style: bodyStyle)];
    }
    final canMark = widget.onToggleInner != null;
    final children = <Widget>[];
    var cursor = 0;
    for (final item in items) {
      if (item.start > cursor) {
        final prose = _body.substring(cursor, item.start).replaceAll(RegExp(r'\n+$'), '');
        if (prose.trim().isNotEmpty) {
          children.add(Text(prose, style: bodyStyle));
          children.add(const SizedBox(height: 4));
        }
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InnerTaskMark(
                done: item.done,
                size: 13,
                onToggle: canMark ? () => _toggle(item) : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.title,
                    style: bodyStyle.copyWith(
                      decoration: item.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: item.done
                          ? (bodyStyle.color ?? AppColors.text)
                              .withValues(alpha: 0.55)
                          : null,
                      decorationThickness: item.done ? 1.15 : null,
                      color: item.done
                          ? (bodyStyle.color ?? AppColors.text)
                              .withValues(alpha: 0.55)
                          : bodyStyle.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      cursor = item.end + 1;
    }
    if (cursor < _body.length) {
      final prose = _body.substring(cursor).trimLeft();
      if (prose.isNotEmpty) {
        children.add(const SizedBox(height: 4));
        children.add(Text(prose, style: bodyStyle));
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.title.isEmpty && _body.isEmpty) return const SizedBox.shrink();

    final width = _bubbleWidth(context);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.title.isNotEmpty) Text(widget.title, style: titleStyle),
                if (widget.title.isNotEmpty && _body.isNotEmpty)
                  const SizedBox(height: 6),
                if (_body.isNotEmpty) ..._bodyChildren(bodyStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
