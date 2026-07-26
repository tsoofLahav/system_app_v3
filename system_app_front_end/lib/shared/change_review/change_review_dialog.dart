import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/glass_surface.dart';

class ChangeReviewDialogShell extends StatelessWidget {
  const ChangeReviewDialogShell({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(16),
        tintOpacity: 0.92,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: child),
                const SizedBox(height: 12),
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
