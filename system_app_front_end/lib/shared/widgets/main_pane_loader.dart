import 'package:flutter/material.dart';

import '../../design_system/app_typography.dart';

/// Loading indicator scoped to the main content pane (not sidebar/bottom bar).
class MainPaneLoader extends StatelessWidget {
  const MainPaneLoader({
    super.key,
    this.message,
    this.compact = false,
  });

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: compact ? 18 : null,
      height: compact ? 18 : null,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
      ),
    );

    if (compact) return Center(child: indicator);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: AppTypography.noteBodyStyle),
          ],
        ],
      ),
    );
  }
}
