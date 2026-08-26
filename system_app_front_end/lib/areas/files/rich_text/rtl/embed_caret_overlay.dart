/// Paint-only caret bar for embed [TextField]s — part of the [RTL solution](RTL.md).
///
/// Flutter's native caret uses downstream affinity and sits ahead of Hebrew
/// insertion. Super Editor paints from layout boxes. This overlay does the
/// same without writing `controller.selection` on a keystroke.
///
/// Blink uses a [Timer], not a repeating [AnimationController], so tests that
/// `pumpAndSettle` after focusing a field can still idle.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import './embed_caret_hit.dart';

/// Blinking 2px caret over a focused object field. Unfocused: paints nothing.
class EmbedCaretOverlay extends StatefulWidget {
  const EmbedCaretOverlay({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.color,
    required this.child,
    this.enabled = true,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final Color color;
  final Widget child;
  final bool enabled;

  @override
  State<EmbedCaretOverlay> createState() => _EmbedCaretOverlayState();
}

class _EmbedCaretOverlayState extends State<EmbedCaretOverlay> {
  Timer? _blinkTimer;
  bool _lit = false;
  Rect? _caret;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusOrText);
    widget.controller.addListener(_onFocusOrText);
    _syncBlink(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant EmbedCaretOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusOrText);
      widget.focusNode.addListener(_onFocusOrText);
    }
    if (oldWidget.focusNode != widget.focusNode ||
        oldWidget.controller != widget.controller ||
        oldWidget.enabled != widget.enabled) {
      _syncBlink(rebuild: false);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusOrText);
    widget.controller.removeListener(_onFocusOrText);
    _blinkTimer?.cancel();
    super.dispose();
  }

  bool get _shouldPaint => widget.enabled && widget.focusNode.hasPrimaryFocus;

  void _onFocusOrText() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncBlink();
      _measure();
    });
  }

  void _syncBlink({bool rebuild = true}) {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (!_shouldPaint) {
      if (_lit) {
        _lit = false;
        if (rebuild && mounted) setState(() {});
      }
      return;
    }
    final wasLit = _lit;
    _lit = true;
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_shouldPaint) return;
      setState(() => _lit = !_lit);
    });
    if (!wasLit && rebuild && mounted) setState(() {});
  }

  void _measure() {
    if (!mounted) return;
    if (!_shouldPaint) {
      if (_caret != null) setState(() => _caret = null);
      return;
    }
    final host = context.findRenderObject() as RenderBox?;
    final editable = host == null ? null : _findRenderEditable(host);
    if (editable == null || host == null || !host.hasSize) {
      if (_caret != null) setState(() => _caret = null);
      return;
    }
    final local = embedCaretPaintRect(
      editable: editable,
      selection: widget.controller.selection,
      textLength: widget.controller.text.length,
    );
    final next = local == null
        ? null
        : MatrixUtils.transformRect(editable.getTransformTo(host), local);
    if (_caret != next) setState(() => _caret = next);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return CustomPaint(
      foregroundPainter: EmbedCaretPainter(
        rect: _caret,
        color: widget.color,
        visible: _shouldPaint && _caret != null && _lit,
      ),
      child: widget.child,
    );
  }
}

class EmbedCaretPainter extends CustomPainter {
  EmbedCaretPainter({
    required this.rect,
    required this.color,
    required this.visible,
  });

  final Rect? rect;
  final Color color;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || rect == null) return;
    canvas.drawRect(rect!, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant EmbedCaretPainter oldDelegate) {
    return visible != oldDelegate.visible ||
        color != oldDelegate.color ||
        rect != oldDelegate.rect;
  }
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found;
}
