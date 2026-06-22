import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';

enum _HandleKind {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class ImageBlockWidget extends StatefulWidget {
  const ImageBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.maxWidth = 480,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final double maxWidth;

  @override
  State<ImageBlockWidget> createState() => _ImageBlockWidgetState();
}

class _ImageBlockWidgetState extends State<ImageBlockWidget> {
  double? _dragWidth;
  double? _dragHeight;
  double? _naturalWidth;
  double? _naturalHeight;
  bool _selected = true;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  String? _resolvedUrl;
  final _focusNode = FocusNode();

  static const _minSize = 48.0;
  static const _maxHeight = 720.0;
  static const _handleSize = 10.0;
  static const _handleHit = 18.0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted) {
        setState(() => _selected = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final url = _imageUrl;
    if (_resolvedUrl != url) {
      _resolvedUrl = url;
      _naturalWidth = null;
      _naturalHeight = null;
      _resolveNaturalSize(url);
    }
  }

  @override
  void didUpdateWidget(ImageBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.block.content['image_path'];
    final newPath = widget.block.content['image_path'];
    if (oldPath != newPath) {
      _resolvedUrl = null;
    }
    if (_dragWidth == null &&
        _dragHeight == null &&
        (oldWidget.block.content['width'] != widget.block.content['width'] ||
            oldWidget.block.content['height'] != widget.block.content['height'])) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _detachImageListener();
    _focusNode.dispose();
    super.dispose();
  }

  String get _imageUrl {
    final path = widget.block.content['image_path'] as String? ?? '';
    return path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
  }

  double get _aspectRatio {
    if (_naturalWidth != null &&
        _naturalHeight != null &&
        _naturalHeight! > 0) {
      return _naturalWidth! / _naturalHeight!;
    }
    return 4 / 3;
  }

  double _defaultHeight(double width) => width / _aspectRatio;

  (double width, double height) _displaySize(double maxWidth) {
    final storedW = (widget.block.content['width'] as num?)?.toDouble();
    final storedH = (widget.block.content['height'] as num?)?.toDouble();

    var width = _dragWidth ?? storedW ?? maxWidth;
    var height = _dragHeight ??
        storedH ??
        (storedW != null ? storedW / _aspectRatio : _defaultHeight(width));

    width = width.clamp(_minSize, maxWidth);
    height = height.clamp(_minSize, _maxHeight);
    return (width, height);
  }

  void _resolveNaturalSize(String url) {
    _detachImageListener();
    final stream =
        NetworkImage(url).resolve(createLocalImageConfiguration(context));
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _naturalWidth = info.image.width.toDouble();
        _naturalHeight = info.image.height.toDouble();
      });
    });
    _imageStream = stream;
    stream.addListener(_imageListener!);
  }

  void _detachImageListener() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  void _applyDrag(_HandleKind kind, Offset delta, double maxWidth) {
    final (w, h) = _displaySize(maxWidth);
    var nextW = w;
    var nextH = h;
    final aspect = _aspectRatio;

    switch (kind) {
      case _HandleKind.right:
        nextW = w + delta.dx;
      case _HandleKind.left:
        nextW = w - delta.dx;
      case _HandleKind.bottom:
        nextH = h + delta.dy;
      case _HandleKind.top:
        nextH = h - delta.dy;
      case _HandleKind.bottomRight:
        nextW = w + delta.dx;
        nextH = h + delta.dy;
        if (delta.dx.abs() >= delta.dy.abs()) {
          nextH = nextW / aspect;
        } else {
          nextW = nextH * aspect;
        }
      case _HandleKind.bottomLeft:
        nextW = w - delta.dx;
        nextH = h + delta.dy;
        if (delta.dx.abs() >= delta.dy.abs()) {
          nextH = nextW / aspect;
        } else {
          nextW = nextH * aspect;
        }
      case _HandleKind.topRight:
        nextW = w + delta.dx;
        nextH = h - delta.dy;
        if (delta.dx.abs() >= delta.dy.abs()) {
          nextH = nextW / aspect;
        } else {
          nextW = nextH * aspect;
        }
      case _HandleKind.topLeft:
        nextW = w - delta.dx;
        nextH = h - delta.dy;
        if (delta.dx.abs() >= delta.dy.abs()) {
          nextH = nextW / aspect;
        } else {
          nextW = nextH * aspect;
        }
    }

    setState(() {
      _dragWidth = nextW.clamp(_minSize, maxWidth);
      _dragHeight = nextH.clamp(_minSize, _maxHeight);
      _selected = true;
    });
  }

  void _commitSize(double maxWidth) {
    final (w, h) = _displaySize(maxWidth);
    final next = Map<String, dynamic>.from(widget.block.content);
    next['width'] = w.round();
    next['height'] = h.round();
    widget.onChanged(next);
    setState(() {
      _dragWidth = null;
      _dragHeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.block.content['image_path'] as String? ?? '';
    if (path.isEmpty) return const SizedBox.shrink();

    final url = _imageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : widget.maxWidth;
          final (width, height) = _displaySize(maxW);

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() => _selected = true);
              _focusNode.requestFocus();
            },
            child: Focus(
              focusNode: _focusNode,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selected
                            ? AppColors.text.withValues(alpha: 0.35)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Image.network(
                      url,
                      width: width,
                      height: height,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                  if (_selected) ..._buildHandles(maxW, width, height),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildHandles(double maxW, double width, double height) {
    const inset = _handleHit / 2;
    final positions = <_HandleKind, Alignment>{
      _HandleKind.topLeft: Alignment.topLeft,
      _HandleKind.top: Alignment.topCenter,
      _HandleKind.topRight: Alignment.topRight,
      _HandleKind.right: Alignment.centerRight,
      _HandleKind.bottomRight: Alignment.bottomRight,
      _HandleKind.bottom: Alignment.bottomCenter,
      _HandleKind.bottomLeft: Alignment.bottomLeft,
      _HandleKind.left: Alignment.centerLeft,
    };

    return [
      for (final entry in positions.entries)
        Positioned(
          left: entry.value.x < 0
              ? -inset
              : entry.value.x == 0
                  ? width / 2 - inset
                  : null,
          top: entry.value.y < 0
              ? -inset
              : entry.value.y == 0
                  ? height / 2 - inset
                  : null,
          right: entry.value.x > 0 ? -inset : null,
          bottom: entry.value.y > 0 ? -inset : null,
          child: _ResizeHandle(
            kind: entry.key,
            onDrag: (delta) => _applyDrag(entry.key, delta, maxW),
            onDragEnd: () => _commitSize(maxW),
          ),
        ),
    ];
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.kind,
    required this.onDrag,
    required this.onDragEnd,
  });

  final _HandleKind kind;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _lastGlobal;

  MouseCursor get _cursor => switch (widget.kind) {
        _HandleKind.topLeft || _HandleKind.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        _HandleKind.topRight || _HandleKind.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        _HandleKind.top || _HandleKind.bottom => SystemMouseCursors.resizeUpDown,
        _HandleKind.left || _HandleKind.right =>
          SystemMouseCursors.resizeLeftRight,
      };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _lastGlobal = d.globalPosition,
        onPanUpdate: (d) {
          if (_lastGlobal == null) return;
          final delta = d.globalPosition - _lastGlobal!;
          _lastGlobal = d.globalPosition;
          widget.onDrag(delta);
        },
        onPanEnd: (_) {
          _lastGlobal = null;
          widget.onDragEnd();
        },
        onPanCancel: () {
          _lastGlobal = null;
          widget.onDragEnd();
        },
        child: SizedBox(
          width: _ImageBlockWidgetState._handleHit,
          height: _ImageBlockWidgetState._handleHit,
          child: Center(
            child: Container(
              width: _ImageBlockWidgetState._handleSize,
              height: _ImageBlockWidgetState._handleSize,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AppColors.text.withValues(alpha: 0.45),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
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
