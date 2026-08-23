import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/table_grid_nav.dart';

void main() {
  group('TableGridNav LTR grid', () {
    test('physical left moves to a lower column', () {
      final next = TableGridNav.move(
        direction: AxisDirection.left,
        gridRtl: false,
        row: 0,
        col: 1,
        rowCount: 2,
        columnCount: 3,
      );
      expect(next.stayed, isFalse);
      expect(next.row, 0);
      expect(next.col, 0);
      expect(next.enterFrom, TableGridEnterFrom.visualRight);
    });

    test('physical right moves to a higher column', () {
      final next = TableGridNav.move(
        direction: AxisDirection.right,
        gridRtl: false,
        row: 0,
        col: 0,
        rowCount: 2,
        columnCount: 3,
      );
      expect(next.col, 1);
      expect(next.enterFrom, TableGridEnterFrom.visualLeft);
    });

    test('physical left at col 0 stays', () {
      final next = TableGridNav.move(
        direction: AxisDirection.left,
        gridRtl: false,
        row: 0,
        col: 0,
        rowCount: 1,
        columnCount: 2,
      );
      expect(next.stayed, isTrue);
      expect(next.col, 0);
    });
  });

  group('TableGridNav RTL grid (Hebrew UI)', () {
    test('physical left moves to a higher column (visual left)', () {
      final next = TableGridNav.move(
        direction: AxisDirection.left,
        gridRtl: true,
        row: 0,
        col: 0,
        rowCount: 1,
        columnCount: 3,
      );
      expect(next.stayed, isFalse);
      expect(next.col, 1);
      expect(next.enterFrom, TableGridEnterFrom.visualRight);
    });

    test('physical right moves to a lower column (visual right)', () {
      final next = TableGridNav.move(
        direction: AxisDirection.right,
        gridRtl: true,
        row: 0,
        col: 1,
        rowCount: 1,
        columnCount: 3,
      );
      expect(next.col, 0);
      expect(next.enterFrom, TableGridEnterFrom.visualLeft);
    });

    test('physical left at the last column stays', () {
      final next = TableGridNav.move(
        direction: AxisDirection.left,
        gridRtl: true,
        row: 0,
        col: 2,
        rowCount: 1,
        columnCount: 3,
      );
      expect(next.stayed, isTrue);
      expect(next.col, 2);
    });
  });

  group('TableGridNav landing', () {
    test('LTR dest: enter from visual right lands at logical end', () {
      final next = TableGridNav.move(
        direction: AxisDirection.left,
        gridRtl: false,
        row: 0,
        col: 1,
        rowCount: 1,
        columnCount: 2,
      );
      expect(next.landAtLogicalEnd(destRtl: false), isTrue);
      expect(next.landAtLogicalEnd(destRtl: true), isFalse);
    });

    test('RTL dest: enter from visual left lands at logical end', () {
      final next = TableGridNav.move(
        direction: AxisDirection.right,
        gridRtl: true,
        row: 0,
        col: 1,
        rowCount: 1,
        columnCount: 2,
      );
      expect(next.landAtLogicalEnd(destRtl: true), isTrue);
      expect(next.landAtLogicalEnd(destRtl: false), isFalse);
    });

    test('down lands at start; up lands at end (ignore dest RTL)', () {
      final down = TableGridNav.move(
        direction: AxisDirection.down,
        gridRtl: false,
        row: 0,
        col: 1,
        rowCount: 3,
        columnCount: 2,
      );
      expect(down.row, 1);
      expect(down.landAtLogicalEnd(destRtl: true), isFalse);
      expect(down.landAtLogicalEnd(destRtl: false), isFalse);

      final up = TableGridNav.move(
        direction: AxisDirection.up,
        gridRtl: true,
        row: 2,
        col: 1,
        rowCount: 3,
        columnCount: 2,
      );
      expect(up.row, 1);
      expect(up.landAtLogicalEnd(destRtl: true), isTrue);
      expect(up.landAtLogicalEnd(destRtl: false), isTrue);
    });
  });
}
