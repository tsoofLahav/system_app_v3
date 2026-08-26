import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Describes how file note rectangles are arranged on the topic canvas.
class FileLayoutDefinition {
  const FileLayoutDefinition({
    required this.id,
    required this.label,
    required this.minSlots,
    required this.builder,
    this.fixedCapacity,
  });

  final String id;
  final String label;

  /// Minimum main files required to select this layout.
  final int minSlots;

  /// When set, only this many files appear in the primary canvas; extras overflow.
  final int? fixedCapacity;

  final Widget Function(BuildContext context, List<Widget> slots) builder;
}

abstract final class FileLayouts {
  /// Follows file count: 1 → single, 2 → split, 3+ → hero.
  /// Stored until the user picks a layout.
  static const auto = 'auto';
  static const single = 'single';
  static const split = 'split';
  static const hero = 'hero';
  static const grid = 'grid';

  /// Legacy stored ids — still read, never offered in the picker.
  static const heroLeft = 'hero_left';
  static const heroRight = 'hero_right';
  static const row = 'row';

  static const List<FileLayoutDefinition> all = [
    FileLayoutDefinition(id: grid, label: 'Grid', minSlots: 1, builder: _grid),
    FileLayoutDefinition(
      id: single,
      label: 'Single',
      minSlots: 1,
      fixedCapacity: 1,
      builder: _single,
    ),
    FileLayoutDefinition(
      id: split,
      label: 'Split',
      minSlots: 2,
      fixedCapacity: 2,
      builder: _split,
    ),
    FileLayoutDefinition(
      id: hero,
      label: 'Three files',
      minSlots: 3,
      fixedCapacity: 3,
      builder: _hero,
    ),
  ];

  /// Maps leftover stored ids onto the four pickable layouts.
  static String canonicalId(String id) {
    switch (id) {
      case heroLeft:
      case heroRight:
      case hero:
        return hero;
      case row:
        return grid;
      default:
        return id;
    }
  }

  static FileLayoutDefinition byId(String id) {
    if (id == auto) return byId(single);
    final canonical = canonicalId(id);
    return all.firstWhere((l) => l.id == canonical, orElse: () => all.first);
  }

  /// Persist [auto] when the pick is still the count-based default.
  static String storedLayoutId(String layoutId, int fileCount) {
    final resolved = layoutId == auto
        ? bestForFileCount(fileCount)
        : canonicalId(layoutId);
    if (resolved == bestForFileCount(fileCount)) return auto;
    return resolved;
  }

  static bool isAvailable(String id, int fileCount) {
    if (fileCount < 1) return false;
    return fileCount >= byId(id).minSlots;
  }

  static String bestForFileCount(int fileCount) {
    if (fileCount >= 3) return hero;
    if (fileCount == 2) return split;
    return single;
  }

  static int? fixedCapacityFor(String id) => byId(id).fixedCapacity;

  /// Default height for a primary file slot inside a scroll view.
  static const primarySlotMinHeight = 540.0;

  /// Extra space kept below primary files before the next section scrolls in.
  static const secondarySectionReserve = 120.0;

  /// Height for primary file layouts — grows with the window before content below appears.
  static double primarySlotHeight(
    BuildContext context, {
    required double canvasPaddingTop,
    required double canvasPaddingBottom,
    double reservedAbove = 0,
    double reservedBelow = 0,
  }) {
    final viewport = MediaQuery.sizeOf(context).height;
    final available =
        viewport -
        canvasPaddingTop -
        canvasPaddingBottom -
        reservedAbove -
        reservedBelow;
    return math.max(primarySlotMinHeight, available);
  }

  /// Height of one file on a phone, where files always stack.
  ///
  /// Short of the viewport on purpose: the next file peeking in is what tells
  /// the user the topic continues below.
  static double phoneSlotHeight(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    return math.max(320.0, viewport * 0.72);
  }

  static double _slotHeightFromConstraints(BoxConstraints constraints) {
    if (constraints.maxHeight.isFinite) return constraints.maxHeight;
    return primarySlotMinHeight;
  }

  static Widget _single(BuildContext context, List<Widget> slots) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = _slotHeightFromConstraints(constraints);
        return SizedBox(
          height: h,
          child: slots.isNotEmpty ? slots.first : const SizedBox.shrink(),
        );
      },
    );
  }

  static Widget _split(BuildContext context, List<Widget> slots) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = _slotHeightFromConstraints(constraints);
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const SizedBox(width: AppLayoutSpacing.gap),
                Expanded(child: slots[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Big pane first in the [Row] — start edge, so left in LTR and right in RTL.
  static Widget _hero(BuildContext context, List<Widget> slots) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = _slotHeightFromConstraints(constraints);
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _slot(slots, 0)),
              const SizedBox(width: AppLayoutSpacing.gap),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(child: _slot(slots, 1)),
                    const SizedBox(height: AppLayoutSpacing.gap),
                    Expanded(child: _slot(slots, 2)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _grid(BuildContext context, List<Widget> slots) {
    return Wrap(
      spacing: AppLayoutSpacing.gap,
      runSpacing: AppLayoutSpacing.gap,
      children: [
        for (var i = 0; i < slots.length; i++)
          SizedBox(width: 340, height: 300, child: slots[i]),
      ],
    );
  }

  static Widget _slot(List<Widget> slots, int index) {
    if (index < slots.length) return slots[index];
    return const SizedBox.shrink();
  }
}

abstract final class AppLayoutSpacing {
  static const gap = 8.0;
}
