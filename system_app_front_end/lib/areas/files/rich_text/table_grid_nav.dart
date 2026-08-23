import 'package:flutter/painting.dart';

/// Physical pad/hardware arrows → a visual table cell.
///
/// Policy: [`rtl/RTL.md`](rtl/RTL.md). Grid columns follow app [Directionality]
/// (Hebrew UI paints col 0 on the right). This is not in-cell caret math —
/// first-strong direction stays in `rtl/`.
///
/// [physical] is always screen left/right/up/down. The pad never mirrors;
/// this is the only place column order flips for Hebrew UI.
enum TableGridEnterFrom { visualLeft, visualRight, above, below }

class TableGridMove {
  const TableGridMove({
    required this.row,
    required this.col,
    required this.stayed,
    this.enterFrom,
  });

  final int row;
  final int col;

  /// Already at that visual edge of the grid — caller stays or exits.
  final bool stayed;

  /// Side the caret entered from. Null when [stayed].
  final TableGridEnterFrom? enterFrom;

  /// Logical end of the destination string (offset = length).
  ///
  /// Horizontal landing is the **visual** edge we entered from, converted
  /// with the destination cell's first-strong direction: visual right is
  /// logical end in LTR and logical start in RTL. Vertical stays
  /// from-below → end, from-above → start.
  bool landAtLogicalEnd({required bool destRtl}) {
    final from = enterFrom;
    if (stayed || from == null) return false;
    return switch (from) {
      TableGridEnterFrom.visualRight => !destRtl,
      TableGridEnterFrom.visualLeft => destRtl,
      TableGridEnterFrom.above => false,
      TableGridEnterFrom.below => true,
    };
  }
}

abstract final class TableGridNav {
  /// Next cell for a physical [direction]. Out of bounds → [TableGridMove.stayed].
  static TableGridMove move({
    required AxisDirection direction,
    required bool gridRtl,
    required int row,
    required int col,
    required int rowCount,
    required int columnCount,
  }) {
    if (rowCount <= 0 || columnCount <= 0) {
      return TableGridMove(row: row, col: col, stayed: true);
    }

    var nextRow = row;
    var nextCol = col;
    late final TableGridEnterFrom enterFrom;

    switch (direction) {
      case AxisDirection.left:
        nextCol = gridRtl ? col + 1 : col - 1;
        enterFrom = TableGridEnterFrom.visualRight;
      case AxisDirection.right:
        nextCol = gridRtl ? col - 1 : col + 1;
        enterFrom = TableGridEnterFrom.visualLeft;
      case AxisDirection.up:
        nextRow = row - 1;
        enterFrom = TableGridEnterFrom.below;
      case AxisDirection.down:
        nextRow = row + 1;
        enterFrom = TableGridEnterFrom.above;
    }

    if (nextRow < 0 ||
        nextRow >= rowCount ||
        nextCol < 0 ||
        nextCol >= columnCount) {
      return TableGridMove(row: row, col: col, stayed: true);
    }
    return TableGridMove(
      row: nextRow,
      col: nextCol,
      stayed: false,
      enterFrom: enterFrom,
    );
  }
}
