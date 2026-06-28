import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import 'board_content.dart';

/// Dims the area outside the crop selection.
class BoardCropShade extends StatelessWidget {
  const BoardCropShade({
    super.key,
    required this.itemWidth,
    required this.itemHeight,
    required this.selection,
  });

  final double itemWidth;
  final double itemHeight;
  final Rect selection;

  @override
  Widget build(BuildContext context) {
    final color = Colors.black.withValues(alpha: 0.45);
    return Stack(
      children: [
        if (selection.top > 0)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: selection.top,
            child: ColoredBox(color: color),
          ),
        if (selection.bottom < itemHeight)
          Positioned(
            left: 0,
            top: selection.bottom,
            right: 0,
            bottom: 0,
            child: ColoredBox(color: color),
          ),
        if (selection.left > 0)
          Positioned(
            left: 0,
            top: selection.top,
            width: selection.left,
            height: selection.height,
            child: ColoredBox(color: color),
          ),
        if (selection.right < itemWidth)
          Positioned(
            left: selection.right,
            top: selection.top,
            right: 0,
            height: selection.height,
            child: ColoredBox(color: color),
          ),
      ],
    );
  }
}

class BoardCropSelectionFrame extends StatelessWidget {
  const BoardCropSelectionFrame({
    super.key,
    required this.selection,
    required this.onMove,
    required this.onMoveEnd,
    required this.onResize,
    required this.onResizeEnd,
  });

  final Rect selection;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final void Function(BoardCropHandle handle, Offset delta) onResize;
  final VoidCallback onResizeEnd;

  static const _accent = AppColors.aiCyan;
  static const _arm = 14.0;
  static const _thickness = 2.0;
  static const _hit = 20.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: selection,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onMove(d.delta),
            onPanEnd: (_) => onMoveEnd(),
            onPanCancel: onMoveEnd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: _accent, width: _thickness),
              ),
            ),
          ),
        ),
        for (final handle in BoardCropHandle.values)
          _CropHandle(
            handle: handle,
            selection: selection,
            onResize: onResize,
            onResizeEnd: onResizeEnd,
          ),
      ],
    );
  }
}

class _CropHandle extends StatefulWidget {
  const _CropHandle({
    required this.handle,
    required this.selection,
    required this.onResize,
    required this.onResizeEnd,
  });

  final BoardCropHandle handle;
  final Rect selection;
  final void Function(BoardCropHandle handle, Offset delta) onResize;
  final VoidCallback onResizeEnd;

  @override
  State<_CropHandle> createState() => _CropHandleState();
}

class _CropHandleState extends State<_CropHandle> {
  Offset? _lastGlobal;

  MouseCursor get _cursor => switch (widget.handle) {
        BoardCropHandle.topLeft || BoardCropHandle.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        BoardCropHandle.topRight || BoardCropHandle.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        BoardCropHandle.top || BoardCropHandle.bottom =>
          SystemMouseCursors.resizeUpDown,
        BoardCropHandle.left || BoardCropHandle.right =>
          SystemMouseCursors.resizeLeftRight,
      };

  @override
  Widget build(BuildContext context) {
    final sel = widget.selection;
    const arm = BoardCropSelectionFrame._arm;
    const hit = BoardCropSelectionFrame._hit;
    const t = BoardCropSelectionFrame._thickness;
    const color = BoardCropSelectionFrame._accent;

    final (left, top) = switch (widget.handle) {
      BoardCropHandle.topLeft => (sel.left - hit / 2, sel.top - hit / 2),
      BoardCropHandle.top => (
          sel.left + sel.width / 2 - hit / 2,
          sel.top - hit / 2,
        ),
      BoardCropHandle.topRight => (
          sel.right - hit / 2,
          sel.top - hit / 2,
        ),
      BoardCropHandle.right => (
          sel.right - hit / 2,
          sel.top + sel.height / 2 - hit / 2,
        ),
      BoardCropHandle.bottomRight => (
          sel.right - hit / 2,
          sel.bottom - hit / 2,
        ),
      BoardCropHandle.bottom => (
          sel.left + sel.width / 2 - hit / 2,
          sel.bottom - hit / 2,
        ),
      BoardCropHandle.bottomLeft => (
          sel.left - hit / 2,
          sel.bottom - hit / 2,
        ),
      BoardCropHandle.left => (
          sel.left - hit / 2,
          sel.top + sel.height / 2 - hit / 2,
        ),
    };

    Widget glyph;
    switch (widget.handle) {
      case BoardCropHandle.topLeft:
        glyph = _cornerBracket(arm, t, color, flipH: false, flipV: false);
      case BoardCropHandle.topRight:
        glyph = _cornerBracket(arm, t, color, flipH: true, flipV: false);
      case BoardCropHandle.bottomLeft:
        glyph = _cornerBracket(arm, t, color, flipH: false, flipV: true);
      case BoardCropHandle.bottomRight:
        glyph = _cornerBracket(arm, t, color, flipH: true, flipV: true);
      case BoardCropHandle.top:
      case BoardCropHandle.bottom:
        glyph = Container(
          width: arm,
          height: t,
          color: color,
        );
      case BoardCropHandle.left:
      case BoardCropHandle.right:
        glyph = Container(
          width: t,
          height: arm,
          color: color,
        );
    }

    return Positioned(
      left: left,
      top: top,
      width: hit,
      height: hit,
      child: MouseRegion(
        cursor: _cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _lastGlobal = d.globalPosition,
          onPanUpdate: (d) {
            if (_lastGlobal == null) return;
            final delta = d.globalPosition - _lastGlobal!;
            _lastGlobal = d.globalPosition;
            widget.onResize(widget.handle, delta);
          },
          onPanEnd: (_) {
            _lastGlobal = null;
            widget.onResizeEnd();
          },
          onPanCancel: () {
            _lastGlobal = null;
            widget.onResizeEnd();
          },
          child: Center(child: glyph),
        ),
      ),
    );
  }

  Widget _cornerBracket(
    double arm,
    double t,
    Color color, {
    required bool flipH,
    required bool flipV,
  }) {
    return SizedBox(
      width: arm,
      height: arm,
      child: CustomPaint(
        painter: _CornerBracketPainter(
          color: color,
          thickness: t,
          arm: arm,
          flipH: flipH,
          flipV: flipV,
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({
    required this.color,
    required this.thickness,
    required this.arm,
    required this.flipH,
    required this.flipV,
  });

  final Color color;
  final double thickness;
  final double arm;
  final bool flipH;
  final bool flipV;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.save();
    if (flipH) canvas.translate(size.width, 0);
    if (flipV) canvas.translate(0, size.height);
    if (flipH) canvas.scale(-1, 1);
    if (flipV) canvas.scale(1, -1);

    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) => false;
}
