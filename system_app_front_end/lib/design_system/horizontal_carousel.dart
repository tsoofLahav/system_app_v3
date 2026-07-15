import 'package:flutter/material.dart';

/// Shared center-focus horizontal carousel math and snap helpers.
class HorizontalCarouselMetrics {
  const HorizontalCarouselMetrics({
    required this.itemWidth,
    required this.itemSpacing,
    this.snapEpsilon = 1.5,
    this.emphasisDivisorFactor = 1.35,
  });

  final double itemWidth;
  final double itemSpacing;
  final double snapEpsilon;
  final double emphasisDivisorFactor;

  double stride() => itemWidth + itemSpacing;

  double sidePadding(double viewportWidth) {
    return ((viewportWidth - itemWidth) / 2).clamp(0.0, double.infinity);
  }

  int centeredIndex({
    required double viewportWidth,
    required double scrollOffset,
    required int itemCount,
  }) {
    if (itemCount <= 0) return 0;

    final padding = sidePadding(viewportWidth);
    final center = scrollOffset + viewportWidth / 2;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < itemCount; i++) {
      final itemCenter = padding + i * stride() + itemWidth / 2;
      final distance = (itemCenter - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double emphasisForIndex({
    required int index,
    required double viewportWidth,
    required double scrollOffset,
  }) {
    final padding = sidePadding(viewportWidth);
    final itemCenter = padding + index * stride() + itemWidth / 2;
    final viewportCenter = scrollOffset + viewportWidth / 2;
    final distance = (itemCenter - viewportCenter).abs();
    return (1 - (distance / (itemWidth * emphasisDivisorFactor)).clamp(0.0, 1.0))
        .toDouble();
  }

  double snapTargetOffset({
    required int index,
    required double viewportWidth,
    required double maxScrollExtent,
  }) {
    final padding = sidePadding(viewportWidth);
    return (padding + index * stride() + itemWidth / 2 - viewportWidth / 2)
        .clamp(0.0, maxScrollExtent);
  }
}

class HorizontalCarouselController {
  HorizontalCarouselController({
    required this.metrics,
    required ScrollController scrollController,
    required VoidCallback onChanged,
  }) : _scrollController = scrollController,
       _onChanged = onChanged {
    _scrollController.addListener(_handleScroll);
  }

  final HorizontalCarouselMetrics metrics;
  final ScrollController _scrollController;
  final VoidCallback _onChanged;

  double scrollOffset = 0;
  bool isSnapping = false;

  void dispose() {
    _scrollController.removeListener(_handleScroll);
  }

  void _handleScroll() {
    scrollOffset = _scrollController.offset;
    _onChanged();
  }

  void snapToNearest(int itemCount) {
    if (isSnapping || !_scrollController.hasClients || itemCount <= 0) return;

    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final bestIndex = metrics.centeredIndex(
      viewportWidth: viewport,
      scrollOffset: position.pixels,
      itemCount: itemCount,
    );
    scrollToIndex(
      index: bestIndex,
      itemCount: itemCount,
      viewportWidth: viewport,
    );
  }

  void scrollToIndex({
    required int index,
    required int itemCount,
    required double viewportWidth,
  }) {
    if (!_scrollController.hasClients || itemCount <= 0) return;

    final position = _scrollController.position;
    final target = metrics.snapTargetOffset(
      index: index.clamp(0, itemCount - 1),
      viewportWidth: viewportWidth,
      maxScrollExtent: position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < metrics.snapEpsilon) return;

    isSnapping = true;
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          isSnapping = false;
          scrollOffset = _scrollController.offset;
          _onChanged();
        });
  }
}

CarouselItemEmphasis carouselEmphasisStyle(double emphasis) {
  return CarouselItemEmphasis(
    scale: 0.86 + (0.14 * emphasis),
    opacity: 0.82 + (0.18 * emphasis),
    lift: (1 - emphasis) * 8,
  );
}

class CarouselItemEmphasis {
  const CarouselItemEmphasis({
    required this.scale,
    required this.opacity,
    required this.lift,
  });

  final double scale;
  final double opacity;
  final double lift;
}
