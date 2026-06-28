import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/registry/file_behavior_registry.dart';
import 'package:system_app_front_end/core/registry/file_registry.dart';
import 'package:system_app_front_end/features/blocks/board_clipboard.dart';
import 'package:system_app_front_end/features/blocks/board_content.dart';

void main() {
  test('board file type is registered as additional by default', () {
    expect(
      FileRegistry.isMainFile(
        topicType: 'area',
        fileType: 'board',
        isMainTopic: true,
      ),
      isFalse,
    );
    expect(
      FileRegistry.allFileTypes.any((f) => f.type == 'board'),
      isTrue,
    );
  });

  test('board profile has no trailing text and one board block', () {
    final profile = FileBehaviorRegistry.profileForFileType('board');
    expect(profile.inlineInsertDefault, isNull);
    expect(profile.defaultBlocks.length, 1);
    expect(profile.defaultBlocks.first.type, 'board');
    expect(profile.contextMenuBlocks, isEmpty);
  });

  test('board content round-trips items', () {
    final items = [
      const BoardItem(
        id: '1',
        imagePath: '/images/a.png',
        filename: 'a.png',
        x: 10,
        y: 20,
        width: 100,
        height: 80,
        zIndex: 0,
        cropLeft: 0.1,
        cropTop: 0.2,
        cropWidth: 0.5,
        cropHeight: 0.6,
      ),
    ];
    final restored = boardItemsFromContent(boardContentFromItems(items));
    expect(restored.length, 1);
    expect(restored.first.imagePath, '/images/a.png');
    expect(restored.first.x, 10);
    expect(restored.first.cropWidth, 0.5);
  });

  test('board content preserves canvas size and background', () {
    const items = [
      BoardItem(
        id: '1',
        imagePath: '/images/a.png',
        filename: 'a.png',
        x: 0,
        y: 0,
        width: 100,
        height: 80,
        zIndex: 0,
      ),
    ];
    final base = {
      'canvas_width': 800,
      'canvas_height': 600,
      'background_color': 0xFFE8F4FC,
      'items': [],
    };
    final encoded = boardContentFromItems(items, base: base);
    expect(boardContentCanvasWidth(encoded), 800);
    expect(boardContentCanvasHeight(encoded), 600);
    expect(
      boardContentBackgroundColor(encoded),
      const Color(0xFFE8F4FC),
    );
  });

  test('board clipboard payload round-trips item json', () {
    const item = BoardItem(
      id: '3',
      imagePath: '/images/b.png',
      filename: 'b.png',
      x: 12,
      y: 34,
      width: 120,
      height: 90,
      zIndex: 2,
    );
    final payload = '$boardClipMagic${jsonEncode(item.toJson())}';
    final restored = boardItemFromClipboardText(payload);
    expect(restored?.id, '3');
    expect(restored?.imagePath, '/images/b.png');
    expect(restored?.x, 12);
  });

  test('board crop metrics map source region to display size', () {
    const item = BoardItem(
      id: '1',
      imagePath: '/images/a.png',
      filename: 'a.png',
      x: 0,
      y: 0,
      width: 200,
      height: 100,
      zIndex: 0,
      cropLeft: 0.25,
      cropTop: 0,
      cropWidth: 0.5,
      cropHeight: 1,
    );
    final metrics = boardItemSourceMetrics(item);
    expect(metrics.sourceW, 400);
    expect(metrics.sourceH, 100);
    expect(metrics.left, 0.25);
    expect(boardItemHasCrop(item), isTrue);
  });

  test('bakeBoardItemSelection shrinks frame to selection', () {
    const item = BoardItem(
      id: '1',
      imagePath: '/images/a.png',
      filename: 'a.png',
      x: 50,
      y: 60,
      width: 200,
      height: 100,
      zIndex: 0,
    );
    final baked = bakeBoardItemSelection(
      item,
      const Rect.fromLTWH(40, 20, 80, 50),
    );
    expect(baked.x, 90);
    expect(baked.y, 80);
    expect(baked.width, 80);
    expect(baked.height, 50);
    expect(baked.cropLeft, closeTo(0.2, 0.001));
    expect(baked.cropTop, closeTo(0.2, 0.001));
    expect(baked.cropWidth, closeTo(0.4, 0.001));
    expect(baked.cropHeight, closeTo(0.5, 0.001));
    expect(boardItemHasCrop(baked), isTrue);
  });

  test('baked crop round-trips through board content json', () {
    const item = BoardItem(
      id: '1',
      imagePath: '/images/a.png',
      filename: 'a.png',
      x: 0,
      y: 0,
      width: 200,
      height: 100,
      zIndex: 0,
    );
    final baked = bakeBoardItemSelection(
      item,
      const Rect.fromLTWH(50, 25, 100, 50),
    );
    final restored = boardItemsFromContent(
      boardContentFromItems([baked]),
    ).first;
    expect(restored.width, 100);
    expect(restored.height, 50);
    expect(restored.cropWidth, closeTo(0.5, 0.001));
    expect(restored.cropHeight, closeTo(0.5, 0.001));
    expect(boardItemHasCrop(restored), isTrue);
  });

  test('second crop compounds source region from displayed image', () {
    const item = BoardItem(
      id: '1',
      imagePath: '/images/a.png',
      filename: 'a.png',
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      zIndex: 0,
      cropLeft: 0.25,
      cropTop: 0.25,
      cropWidth: 0.5,
      cropHeight: 0.5,
    );
    final baked = bakeBoardItemSelection(
      item,
      const Rect.fromLTWH(25, 12.5, 50, 25),
    );
    expect(baked.width, 50);
    expect(baked.height, 25);
    expect(baked.cropLeft, closeTo(0.375, 0.001));
    expect(baked.cropTop, closeTo(0.375, 0.001));
    expect(baked.cropWidth, closeTo(0.25, 0.001));
    expect(baked.cropHeight, closeTo(0.25, 0.001));
    expect(boardItemHasCrop(baked), isTrue);
  });

  test('expand crop restores previously cropped source region', () {
    const item = BoardItem(
      id: '1',
      imagePath: '/images/a.png',
      filename: 'a.png',
      x: 100,
      y: 50,
      width: 100,
      height: 50,
      zIndex: 0,
      cropLeft: 0.25,
      cropTop: 0.25,
      cropWidth: 0.5,
      cropHeight: 0.5,
    );
    // Virtual canvas is 200x100; extend selection upward by 25px.
    final baked = bakeBoardItemVirtualSelection(
      item,
      const Rect.fromLTWH(50, 0, 100, 75),
    );
    expect(baked.x, 100);
    expect(baked.y, 25);
    expect(baked.width, 100);
    expect(baked.height, 75);
    expect(baked.cropTop, closeTo(0, 0.001));
    expect(baked.cropHeight, closeTo(0.75, 0.001));
    expect(baked.cropLeft, closeTo(0.25, 0.001));
    expect(baked.cropWidth, closeTo(0.5, 0.001));
  });
}
