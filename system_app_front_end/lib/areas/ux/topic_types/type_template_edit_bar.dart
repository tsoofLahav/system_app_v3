import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';

/// Glass Save / Cancel while a type template is open from Preferences.
///
/// Save keeps autosaved edits and goes Home. Cancel restores the snapshot
/// taken on enter, then leaves.
class TypeTemplateEditBar extends StatefulWidget {
  const TypeTemplateEditBar({super.key, required this.state});

  final AppState state;

  @override
  State<TypeTemplateEditBar> createState() => _TypeTemplateEditBarState();
}

class _TypeTemplateEditBarState extends State<TypeTemplateEditBar> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return GlassBarSegment(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(widget.state.cancelTypeTemplateEdit),
            child: Text(s['cancel'], style: AppTypography.metaStyle),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(widget.state.saveTypeTemplateEdit),
            child: Text(s['save'], style: AppTypography.metaStyle),
          ),
        ],
      ),
    );
  }
}
