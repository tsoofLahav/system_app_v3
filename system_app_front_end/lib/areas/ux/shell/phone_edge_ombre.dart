import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import './app_bottom_bar.dart';

/// Thin fade at a phone screen edge so file text disappears into the chrome.
class PhoneEdgeOmbre extends StatelessWidget {
  const PhoneEdgeOmbre({
    super.key,
    required this.atTop,
    required this.edge,
  });

  final bool atTop;
  final Color edge;

  static double heightFor({
    required bool atTop,
    required EdgeInsets padding,
  }) {
    final chrome = atTop
        ? padding.top + AppBottomBarMetrics.phoneBarHeight
        : padding.bottom + AppBottomBarMetrics.phoneBarHeight;
    return chrome + AppBottomBarMetrics.phoneOmbreFade;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.phoneEdgeOmbre(edge: edge, atTop: atTop),
        ),
        child: SizedBox(
          height: heightFor(atTop: atTop, padding: padding),
          width: double.infinity,
        ),
      ),
    );
  }
}
