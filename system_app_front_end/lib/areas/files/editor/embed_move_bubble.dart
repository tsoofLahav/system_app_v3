import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';

/// What a Move Mode keystroke should do. [null] still means consume the event
/// when [embedMoveModeConsumes] is true (Enter/Esc repeats must not type).
enum EmbedMoveKeyCommand { moveUp, moveDown, done }

/// Arrows, Enter, and Esc belong to Move Mode while it is on.
bool embedMoveModeConsumesKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;
}

bool embedMoveModeConsumes(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
  return embedMoveModeConsumesKey(event.logicalKey);
}

/// [done] only on the initial press so holding Enter does not re-fire after close.
EmbedMoveKeyCommand? embedMoveKeyCommandFor(
  LogicalKeyboardKey key, {
  required bool isRepeat,
}) {
  if (!embedMoveModeConsumesKey(key)) return null;
  if (key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return isRepeat ? null : EmbedMoveKeyCommand.done;
  }
  if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
    return EmbedMoveKeyCommand.moveUp;
  }
  return EmbedMoveKeyCommand.moveDown;
}

EmbedMoveKeyCommand? embedMoveKeyCommand(KeyEvent event) {
  if (!embedMoveModeConsumes(event)) return null;
  return embedMoveKeyCommandFor(
    event.logicalKey,
    isRepeat: event is KeyRepeatEvent,
  );
}

/// Floating glass controls for object Move Mode — in the [Overlay], not the
/// file scroll. No scrim. Drag to reposition. Closes via Done, Enter, Esc, or
/// tap outside (armed only after the opening gesture finishes). Arrows nudge.
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
  final _focusNode = FocusNode(debugLabel: 'embedMoveBubble');

  @override
  void initState() {
    super.initState();
    _offset = widget.anchorGlobal;
    // Opening Move Mode is a menu click or shortcut — that pointer-up
    // would otherwise count as "outside" and dismiss the bubble immediately.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _outsideArmed = true);
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!embedMoveModeConsumes(event)) return KeyEventResult.ignored;
    switch (embedMoveKeyCommand(event)) {
      case EmbedMoveKeyCommand.moveUp:
        if (widget.canMoveUp) widget.onMoveUp();
      case EmbedMoveKeyCommand.moveDown:
        if (widget.canMoveDown) widget.onMoveDown();
      case EmbedMoveKeyCommand.done:
        widget.onDone();
      case null:
        break;
    }
    return KeyEventResult.handled;
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
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: _onKey,
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
