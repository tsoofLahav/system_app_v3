import 'package:flutter/material.dart';

import '../../../ui/app_colors.dart';
import '../../../ui/glass_surface.dart';

/// Per-object chrome. Omitted [payload.look] means the type's default.
///
/// Shared looks: card, glass, outline (lines only), fill (wash only), plain.
/// Type extras: ruled (info), grid / lined (table). Image greyscale is a
/// separate payload flag, not a look id.
class ObjectLook {
  ObjectLook._();

  static const card = 'card';
  static const glass = 'glass';
  static const outline = 'outline';
  static const fill = 'fill';
  static const plain = 'plain';
  static const ruled = 'ruled';
  static const grid = 'grid';
  static const lined = 'lined';

  static const infoCard = card;
  static const infoPlain = plain;
  static const infoRuled = ruled;

  static const tableGrid = grid;
  static const tableOpen = 'open';
  static const tableLined = lined;

  static const imageNone = 'none';
  static const imageFrame = 'frame';
  static const imageGreyscale = 'greyscale';
  static const imageFrameGreyscale = 'frame_greyscale';

  static const infoLooks = [card, glass, outline, fill, ruled, plain];
  static const tableLooks = [grid, glass, outline, fill, lined, plain];
  static const imageLooks = [card, glass, outline, fill, plain];

  static const _labels = {
    card: 'lookCard',
    glass: 'lookGlass',
    outline: 'lookOutline',
    fill: 'lookFill',
    plain: 'lookPlain',
    ruled: 'lookRuled',
    grid: 'lookGrid',
    lined: 'lookLined',
    tableOpen: 'lookPlain',
    imageNone: 'lookPlain',
    imageFrame: 'lookCard',
    imageGreyscale: 'lookGreyscale',
    imageFrameGreyscale: 'lookGreyscale',
  };

  static String of(Map<String, dynamic>? payload, {required String fallback}) {
    final look = payload?['look'];
    if (look is String && look.isNotEmpty) return look;
    return fallback;
  }

  static String canonical(String kind, String raw) {
    switch (kind) {
      case 'info':
        return switch (raw) {
          glass || outline || fill || ruled || plain || card => raw,
          _ => card,
        };
      case 'table':
        return switch (raw) {
          tableOpen => plain,
          glass || outline || fill || lined || plain || grid => raw,
          _ => grid,
        };
      case 'image':
        return switch (raw) {
          imageNone || imageGreyscale => plain,
          imageFrame || imageFrameGreyscale => card,
          glass || outline || fill || plain || card => raw,
          _ => plain,
        };
      default:
        return raw;
    }
  }

  static String infoOf(Map<String, dynamic>? payload) =>
      canonical('info', of(payload, fallback: card));

  static String tableOf(Map<String, dynamic>? payload) =>
      canonical('table', of(payload, fallback: grid));

  static String imageOf(Map<String, dynamic>? payload) =>
      canonical('image', of(payload, fallback: imageNone));

  static bool imageGreyscaleOf(Map<String, dynamic>? payload) {
    if (payload?['greyscale'] == true) return true;
    final look = payload?['look'];
    return look == imageGreyscale || look == imageFrameGreyscale;
  }

  static Map<String, dynamic> withLook(
    Map<String, dynamic>? payload,
    String look, {
    bool? greyscale,
  }) {
    final next = <String, dynamic>{...?payload, 'look': look};
    if (greyscale != null) next['greyscale'] = greyscale;
    return next;
  }

  static String labelKey(String kind, String look) {
    if (kind == 'image' && look == card) return 'lookFrame';
    return _labels[look] ?? look;
  }

  static List<String> looksFor(String kind) {
    return switch (kind) {
      'info' => infoLooks,
      'table' => tableLooks,
      'image' => imageLooks,
      _ => const [],
    };
  }

  static bool imageHasFrame(String look) {
    final id = canonical('image', look);
    return id == card || id == glass || id == outline;
  }

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
  switch (ObjectLook.canonical('info', look)) {
    case ObjectLook.plain:
    case ObjectLook.glass:
      return null;
    case ObjectLook.outline:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.noteBorder.withValues(alpha: 0.72),
          width: 0.85,
        ),
      );
    case ObjectLook.fill:
      return BoxDecoration(
        color: AppColors.noteTop.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(6),
      );
    case ObjectLook.ruled:
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
  switch (ObjectLook.canonical('info', look)) {
    case ObjectLook.plain:
      return const EdgeInsets.fromLTRB(2, 2, 2, 4);
    case ObjectLook.ruled:
      return const EdgeInsets.fromLTRB(10, 6, 8, 8);
    default:
      return const EdgeInsets.fromLTRB(8, 6, 8, 8);
  }
}

Widget wrapInfoLook({required String look, required Widget child}) {
  final id = ObjectLook.canonical('info', look);
  final padded = Padding(padding: infoLookPadding(id), child: child);
  if (id == ObjectLook.glass) {
    return GlassSurface.styled(
      style: AppGlassStyle.dragMode,
      borderRadius: BorderRadius.circular(6),
      border: AppGlassStyle.dragModeBorder,
      child: padded,
    );
  }
  final decoration = infoLookDecoration(id);
  if (decoration == null) return padded;
  return DecoratedBox(decoration: decoration, child: padded);
}

Color tableLookBorderColor(String look) {
  final id = ObjectLook.canonical('table', look);
  if (id == ObjectLook.fill) {
    return AppColors.noteTop.withValues(alpha: 0.42);
  }
  return AppColors.noteBorder.withValues(alpha: 0.72);
}

Color? tableLookFillColor(String look) {
  final id = ObjectLook.canonical('table', look);
  if (id == ObjectLook.fill) return AppColors.noteTop.withValues(alpha: 0.42);
  return null;
}

bool tableLookHasOuterBox(String look) {
  final id = ObjectLook.canonical('table', look);
  return id != ObjectLook.plain &&
      id != ObjectLook.lined &&
      id != ObjectLook.tableOpen &&
      id != ObjectLook.glass;
}

bool tableLookHasVerticalRules(String look) {
  final id = ObjectLook.canonical('table', look);
  return id != ObjectLook.lined;
}

bool tableLookIsGlass(String look) =>
    ObjectLook.canonical('table', look) == ObjectLook.glass;

Widget wrapTableLook({required String look, required Widget child}) {
  final id = ObjectLook.canonical('table', look);
  final fill = tableLookFillColor(id);
  var next = child;
  if (fill != null) {
    next = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: next,
    );
  }
  if (id == ObjectLook.glass) {
    return GlassSurface.styled(
      style: AppGlassStyle.dragMode,
      borderRadius: BorderRadius.circular(6),
      border: AppGlassStyle.dragModeBorder,
      child: next,
    );
  }
  return next;
}

Widget wrapImageLook({
  required String look,
  required bool greyscale,
  required Widget child,
}) {
  final id = ObjectLook.canonical('image', look);
  var picture = child;
  if (greyscale) {
    picture = ColorFiltered(
      colorFilter: ObjectLook.greyscaleFilter,
      child: picture,
    );
  }
  picture = ClipRRect(borderRadius: BorderRadius.circular(6), child: picture);
  switch (id) {
    case ObjectLook.glass:
      return GlassSurface.styled(
        style: AppGlassStyle.dragMode,
        borderRadius: BorderRadius.circular(6),
        border: AppGlassStyle.dragModeBorder,
        child: picture,
      );
    case ObjectLook.outline:
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.noteBorder, width: 0.85),
        ),
        child: picture,
      );
    case ObjectLook.fill:
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.noteTop.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: picture),
      );
    case ObjectLook.card:
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.noteBorder, width: 0.85),
        ),
        child: picture,
      );
    default:
      return picture;
  }
}
