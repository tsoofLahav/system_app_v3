import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';

/// Floating glass controls for object Move Mode — in the [Overlay], not the
/// file scroll. No scrim. Drag to reposition. Closes via Done or tap outside
/// (armed only after the opening gesture finishes).
class EmbedMoveBubble extends StatefulWidget {
  const EmbedMoveBubble({
    super.key,
    required this.anchorGlobal,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDone,
    this.canMoveUp = true,
    this.canMoveDown = true,
    this.moveLabel = 'Move',
    this.doneLabel = 'Done',
  });

  /// Top-right of the file editor in global coordinates — bubble opens nearby.
  final Offset anchorGlobal;

  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDone;
  final bool canMoveUp;
  final bool canMoveDown;
  final String moveLabel;
  final String doneLabel;

  @override
  State<EmbedMoveBubble> createState() => _EmbedMoveBubbleState();
}

class _EmbedMoveBubbleState extends State<EmbedMoveBubble> {
  static const _width = 148.0;
  static const _approxHeight = 118.0;

  late Offset _offset;
  var _outsideArmed = false;

  @override
  void initState() {
    super.initState();
    _offset = widget.anchorGlobal;
    // Opening Move Mode is a double-click on the object — that pointer-up
    // would otherwise count as "outside" and dismiss the bubble immediately.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _outsideArmed = true);
      });
    });
  }

  Offset _clampToScreen(Offset raw, Size screen) {
    return Offset(
      raw.dx.clamp(8.0, (screen.width - _width).clamp(8.0, screen.width)),
      raw.dy.clamp(
        8.0,
        (screen.height - _approxHeight).clamp(8.0, screen.height),
      ),
    );
  }

  void _panBy(Offset delta, Size screen) {
    setState(() => _offset = _clampToScreen(_offset + delta, screen));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pos = _clampToScreen(_offset, screen);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: TapRegion(
        onTapOutside: (_) {
          if (!_outsideArmed) return;
          widget.onDone();
        },
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: GlassSurface.styled(
            style: AppGlassStyle.floating,
            borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: SizedBox(
              width: _width - 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => _panBy(d.delta, screen),
                    child: Row(
                      children: [
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 16,
                          color: AppColors.text.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.moveLabel,
                            style: AppTypography.metaStyle.copyWith(
                              color: AppColors.text.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MoveIconButton(
                        tooltip: 'Move up',
                        icon: Icons.arrow_upward_rounded,
                        onPressed: widget.canMoveUp ? widget.onMoveUp : null,
                      ),
                      const SizedBox(width: 4),
                      _MoveIconButton(
                        tooltip: 'Move down',
                        icon: Icons.arrow_downward_rounded,
                        onPressed:
                            widget.canMoveDown ? widget.onMoveDown : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: widget.onDone,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      widget.doneLabel,
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.primary.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w500,
                      ),
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

/// Default global origin for the bubble: top-right inside [editorContext]'s box.
Offset embedMoveBubbleAnchor(BuildContext editorContext) {
  final box = editorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return const Offset(24, 96);
  }
  final origin = box.localToGlobal(Offset.zero);
  return Offset(
    origin.dx + box.size.width - 160,
    origin.dy + 24,
  );
}

class _MoveIconButton extends StatelessWidget {
  const _MoveIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      color: AppColors.text.withValues(alpha: onPressed == null ? 0.28 : 0.78),
    );
  }
}
