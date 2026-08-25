import 'package:flutter/material.dart';

import '../../../ui/app_colors.dart';

/// Per-object chrome. Omitted [payload.look] means the type's default.
class ObjectLook {
  ObjectLook._();

  static const infoCard = 'card';
  static const infoPlain = 'plain';
  static const infoRuled = 'ruled';

  static const tableGrid = 'grid';
  static const tableOpen = 'open';
  static const tableLined = 'lined';

  static const imageNone = 'none';
  static const imageFrame = 'frame';
  static const imageGreyscale = 'greyscale';
  static const imageFrameGreyscale = 'frame_greyscale';

  static const infoLooks = [infoCard, infoPlain, infoRuled];
  static const tableLooks = [tableGrid, tableOpen, tableLined];
  static const imageLooks = [
    imageNone,
    imageFrame,
    imageGreyscale,
    imageFrameGreyscale,
  ];

  static const _infoLabels = {
    infoCard: 'lookCard',
    infoPlain: 'lookPlain',
    infoRuled: 'lookRuled',
  };
  static const _tableLabels = {
    tableGrid: 'lookGrid',
    tableOpen: 'lookOpen',
    tableLined: 'lookLined',
  };
  static const _imageLabels = {
    imageNone: 'lookNone',
    imageFrame: 'lookFrame',
    imageGreyscale: 'lookGreyscale',
    imageFrameGreyscale: 'lookFrameGreyscale',
  };

  static String of(Map<String, dynamic>? payload, {required String fallback}) {
    final look = payload?['look'];
    if (look is String && look.isNotEmpty) return look;
    return fallback;
  }

  static String infoOf(Map<String, dynamic>? payload) =>
      of(payload, fallback: infoCard);

  static String tableOf(Map<String, dynamic>? payload) =>
      of(payload, fallback: tableGrid);

  static String imageOf(Map<String, dynamic>? payload) =>
      of(payload, fallback: imageNone);

  static Map<String, dynamic> withLook(
    Map<String, dynamic>? payload,
    String look,
  ) {
    return {...?payload, 'look': look};
  }

  static String labelKey(String kind, String look) {
    final map = switch (kind) {
      'info' => _infoLabels,
      'table' => _tableLabels,
      'image' => _imageLabels,
      _ => const <String, String>{},
    };
    return map[look] ?? look;
  }

  static List<String> looksFor(String kind) {
    return switch (kind) {
      'info' => infoLooks,
      'table' => tableLooks,
      'image' => imageLooks,
      _ => const [],
    };
  }

  static bool imageHasFrame(String look) =>
      look == imageFrame || look == imageFrameGreyscale;

  static bool imageIsGreyscale(String look) =>
      look == imageGreyscale || look == imageFrameGreyscale;

  static const greyscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}

Decoration? infoLookDecoration(String look) {
  switch (look) {
    case ObjectLook.infoPlain:
      return null;
    case ObjectLook.infoRuled:
      return BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.noteBorder.withValues(alpha: 0.9),
            width: 1.5,
          ),
        ),
      );
    default:
      return AppColors.detailsBlockDecoration();
  }
}

EdgeInsets infoLookPadding(String look) {
  switch (look) {
    case ObjectLook.infoPlain:
      return const EdgeInsets.fromLTRB(2, 2, 2, 4);
    case ObjectLook.infoRuled:
      return const EdgeInsets.fromLTRB(10, 6, 8, 8);
    default:
      return const EdgeInsets.fromLTRB(8, 6, 8, 8);
  }
}

Color tableLookBorderColor() =>
    AppColors.noteBorder.withValues(alpha: 0.72);

bool tableLookHasOuterBox(String look) =>
    look != ObjectLook.tableOpen && look != ObjectLook.tableLined;

bool tableLookHasVerticalRules(String look) => look != ObjectLook.tableLined;
