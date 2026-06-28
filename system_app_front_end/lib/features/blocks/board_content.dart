import 'dart:ui';

class BoardItem {
  const BoardItem({
    required this.id,
    required this.imagePath,
    required this.filename,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropWidth = 1,
    this.cropHeight = 1,
  });

  final String id;
  final String imagePath;
  final String filename;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;

  BoardItem copyWith({
    String? id,
    String? imagePath,
    String? filename,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    double? cropLeft,
    double? cropTop,
    double? cropWidth,
    double? cropHeight,
  }) {
    return BoardItem(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      filename: filename ?? this.filename,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
    );
  }

  /// Sets geometry and source crop in one shot (avoids nullable copyWith pitfalls).
  BoardItem withGeometryAndCrop({
    required double x,
    required double y,
    required double width,
    required double height,
    required double cropLeft,
    required double cropTop,
    required double cropWidth,
    required double cropHeight,
  }) {
    return BoardItem(
      id: id,
      imagePath: imagePath,
      filename: filename,
      x: x,
      y: y,
      width: width,
      height: height,
      zIndex: zIndex,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'image_path': imagePath,
    'filename': filename,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'z_index': zIndex,
    if (cropLeft != 0) 'crop_left': cropLeft,
    if (cropTop != 0) 'crop_top': cropTop,
    if (cropWidth != 1) 'crop_width': cropWidth,
    if (cropHeight != 1) 'crop_height': cropHeight,
  };

  factory BoardItem.fromJson(Map<String, dynamic> json) {
    return BoardItem(
      id: json['id']?.toString() ?? '',
      imagePath: json['image_path'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 200,
      height: (json['height'] as num?)?.toDouble() ?? 150,
      zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
      cropLeft: (json['crop_left'] as num?)?.toDouble() ?? 0,
      cropTop: (json['crop_top'] as num?)?.toDouble() ?? 0,
      cropWidth: (json['crop_width'] as num?)?.toDouble() ?? 1,
      cropHeight: (json['crop_height'] as num?)?.toDouble() ?? 1,
    );
  }
}

List<BoardItem> boardItemsFromContent(Map<String, dynamic> content) {
  final raw = content['items'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => BoardItem.fromJson(Map<String, dynamic>.from(e)))
      .where((item) => item.id.isNotEmpty && item.imagePath.isNotEmpty)
      .toList()
    ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
}

Map<String, dynamic> boardContentFromItems(List<BoardItem> items) {
  return {
    'items': items.map((item) => item.toJson()).toList(),
  };
}

String nextBoardItemId(List<BoardItem> items) {
  var max = 0;
  for (final item in items) {
    final parsed = int.tryParse(item.id);
    if (parsed != null && parsed > max) max = parsed;
  }
  return '${max + 1}';
}

int nextBoardZIndex(List<BoardItem> items) {
  if (items.isEmpty) return 0;
  return items.map((i) => i.zIndex).reduce((a, b) => a > b ? a : b) + 1;
}

(double x, double y) staggerBoardPlacement(List<BoardItem> items) {
  final index = items.length;
  return (24.0 + (index % 4) * 28, 24.0 + (index % 4) * 24);
}

/// Normalized crop rect on the source image (0–1).
({double left, double top, double width, double height}) boardItemCropRect(
  BoardItem item,
) {
  const minCrop = 0.05;
  final width = item.cropWidth.clamp(minCrop, 1.0);
  final height = item.cropHeight.clamp(minCrop, 1.0);
  final left = item.cropLeft.clamp(0.0, 1.0 - width);
  final top = item.cropTop.clamp(0.0, 1.0 - height);
  return (left: left, top: top, width: width, height: height);
}

bool boardItemHasCrop(BoardItem item) {
  const eps = 0.001;
  return item.cropLeft > eps ||
      item.cropTop > eps ||
      item.cropWidth < 1 - eps ||
      item.cropHeight < 1 - eps;
}

/// Maps the visible crop region to the item's width/height on the canvas.
({double sourceW, double sourceH, double left, double top}) boardItemSourceMetrics(
  BoardItem item,
) {
  final crop = boardItemCropRect(item);
  return (
    sourceW: item.width / crop.width,
    sourceH: item.height / crop.height,
    left: crop.left,
    top: crop.top,
  );
}

/// Full source image laid out in crop-edit space (allows expanding/restoring crop).
({
  double fullW,
  double fullH,
  double visibleLeft,
  double visibleTop,
  double canvasX,
  double canvasY,
}) boardItemCropVirtualCanvas(BoardItem item) {
  final crop = boardItemCropRect(item);
  final fullW = item.width / crop.width;
  final fullH = item.height / crop.height;
  final visibleLeft = crop.left * fullW;
  final visibleTop = crop.top * fullH;
  return (
    fullW: fullW,
    fullH: fullH,
    visibleLeft: visibleLeft,
    visibleTop: visibleTop,
    canvasX: item.x - visibleLeft,
    canvasY: item.y - visibleTop,
  );
}

/// Initial crop selection in virtual canvas coordinates.
Rect boardItemInitialCropSelection(BoardItem item) {
  final canvas = boardItemCropVirtualCanvas(item);
  return Rect.fromLTWH(
    canvas.visibleLeft,
    canvas.visibleTop,
    item.width,
    item.height,
  );
}

Rect clampCropSelection(
  Rect selection,
  double maxWidth,
  double maxHeight,
  double minSize,
) {
  var width = selection.width.clamp(minSize, maxWidth);
  var height = selection.height.clamp(minSize, maxHeight);
  final left = selection.left.clamp(0.0, maxWidth - width);
  final top = selection.top.clamp(0.0, maxHeight - height);
  return Rect.fromLTWH(left, top, width, height);
}

enum BoardCropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

Rect resizeCropSelection(
  Rect selection,
  BoardCropHandle handle,
  Offset delta,
  double maxWidth,
  double maxHeight,
  double minSize,
) {
  var left = selection.left;
  var top = selection.top;
  var width = selection.width;
  var height = selection.height;

  switch (handle) {
    case BoardCropHandle.right:
      width += delta.dx;
    case BoardCropHandle.left:
      left += delta.dx;
      width -= delta.dx;
    case BoardCropHandle.bottom:
      height += delta.dy;
    case BoardCropHandle.top:
      top += delta.dy;
      height -= delta.dy;
    case BoardCropHandle.bottomRight:
      width += delta.dx;
      height += delta.dy;
    case BoardCropHandle.bottomLeft:
      left += delta.dx;
      width -= delta.dx;
      height += delta.dy;
    case BoardCropHandle.topRight:
      width += delta.dx;
      top += delta.dy;
      height -= delta.dy;
    case BoardCropHandle.topLeft:
      left += delta.dx;
      width -= delta.dx;
      top += delta.dy;
      height -= delta.dy;
  }

  if (width < minSize) {
    if (handle == BoardCropHandle.left ||
        handle == BoardCropHandle.topLeft ||
        handle == BoardCropHandle.bottomLeft) {
      left -= minSize - width;
    }
    width = minSize;
  }
  if (height < minSize) {
    if (handle == BoardCropHandle.top ||
        handle == BoardCropHandle.topLeft ||
        handle == BoardCropHandle.topRight) {
      top -= minSize - height;
    }
    height = minSize;
  }

  return clampCropSelection(
    Rect.fromLTWH(left, top, width, height),
    maxWidth,
    maxHeight,
    minSize,
  );
}

/// Applies a crop selection in virtual canvas coordinates.
BoardItem bakeBoardItemVirtualSelection(BoardItem item, Rect selection) {
  final canvas = boardItemCropVirtualCanvas(item);
  final sel = clampCropSelection(
    selection,
    canvas.fullW,
    canvas.fullH,
    1,
  );
  const eps = 0.5;
  if ((sel.left - canvas.visibleLeft).abs() <= eps &&
      (sel.top - canvas.visibleTop).abs() <= eps &&
      (sel.width - item.width).abs() <= eps &&
      (sel.height - item.height).abs() <= eps) {
    return item;
  }

  const minCrop = 0.05;
  var cropLeft = sel.left / canvas.fullW;
  var cropTop = sel.top / canvas.fullH;
  var cropWidth = sel.width / canvas.fullW;
  var cropHeight = sel.height / canvas.fullH;

  cropWidth = cropWidth.clamp(minCrop, 1.0);
  cropHeight = cropHeight.clamp(minCrop, 1.0);
  cropLeft = cropLeft.clamp(0.0, 1.0 - cropWidth);
  cropTop = cropTop.clamp(0.0, 1.0 - cropHeight);

  return item.withGeometryAndCrop(
    x: canvas.canvasX + sel.left,
    y: canvas.canvasY + sel.top,
    width: sel.width,
    height: sel.height,
    cropLeft: cropLeft,
    cropTop: cropTop,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
  );
}

/// Applies a crop selection (item-local coords) and returns a new item whose
/// frame matches the selection and whose source crop reflects the chosen region.
BoardItem bakeBoardItemSelection(BoardItem item, Rect selection) {
  final canvas = boardItemCropVirtualCanvas(item);
  final virtual = selection.shift(Offset(canvas.visibleLeft, canvas.visibleTop));
  return bakeBoardItemVirtualSelection(item, virtual);
}
