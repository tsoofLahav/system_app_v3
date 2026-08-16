import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../ui/dialog_metrics.dart';
import '../ui/glass_surface.dart';

class ChangeReviewDialogShell extends StatelessWidget {
  const ChangeReviewDialogShell({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.maxWidth = 640,
    this.maxHeight = 520,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: AppDialogMetrics.windowInset,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
        tintOpacity: 0.92,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: Padding(
            padding: AppDialogMetrics.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppDialogMetrics.titleGap),
                Expanded(child: child),
                const SizedBox(height: AppDialogMetrics.actionsGap),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
