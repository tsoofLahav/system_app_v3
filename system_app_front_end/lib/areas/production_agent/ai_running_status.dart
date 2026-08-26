import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/app_colors.dart';
import '../ui/app_typography.dart';

/// Spinner next to the AI bar while a run is in flight.
///
/// Cancel does not abort the request. It waits for the return, then drops the
/// result instead of opening review / undo / a summary.
class AiRunningStatus extends StatelessWidget {
  const AiRunningStatus({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final canceling = state.aiCancelRequested;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.aiCyan.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          canceling ? s['aiCanceling'] : s['aiRunning'],
          style: AppTypography.metaStyle,
        ),
        if (!canceling) ...[
          const SizedBox(width: 4),
          TextButton(
            onPressed: state.requestCancelAiRun,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(
              s['cancel'],
              style: AppTypography.metaStyle.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
