import 'package:flutter/material.dart';

import '../../ui/app_typography.dart';
import '../../../shared/utils/hardware_keyboard_guard.dart';

/// Loading indicator scoped to the main content pane (not sidebar/bottom bar).
///
/// While this is on screen the user cannot type. Each frame drops any keys
/// Flutter seeded on startup so the editor does not open with a stuck KeyDown.
class MainPaneLoader extends StatefulWidget {
  const MainPaneLoader({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  State<MainPaneLoader> createState() => _MainPaneLoaderState();
}

class _MainPaneLoaderState extends State<MainPaneLoader> {
  @override
  void initState() {
    super.initState();
    releaseTrackedHardwareKeys();
    WidgetsBinding.instance.addPostFrameCallback(_onTick);
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    releaseTrackedHardwareKeys();
    WidgetsBinding.instance.addPostFrameCallback(_onTick);
  }

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: widget.compact ? 18 : null,
      height: widget.compact ? 18 : null,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );

    if (widget.compact) return Center(child: indicator);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          if (widget.message != null) ...[
            const SizedBox(height: 12),
            Text(widget.message!, style: AppTypography.noteBodyStyle),
          ],
        ],
      ),
    );
  }
}
