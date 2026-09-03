import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/app_colors.dart';
import '../ui/app_typography.dart';

/// Spinner next to (desktop) or on (phone) the AI bar while a run is in flight.
///
/// Cancel does not abort the request. It waits for the return, then drops the
/// result instead of opening review / undo / a summary.
class AiRunningStatus extends StatelessWidget {
  const AiRunningStatus({
    super.key,
    required this.state,
    this.overlay = false,
  });

  final AppState state;

  /// Phone: sit on the AI pill so loading + cancel are not missed beside it.
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final canceling = state.aiCancelRequested;
    if (overlay) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.glassTint.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppColors.aiCyan,
                ),
              ),
              const SizedBox(width: 10),
              if (canceling)
                Text(
                  s['aiCanceling'],
                  style: AppTypography.metaStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiCyan,
                  ),
                )
              else
                TextButton(
                  onPressed: state.requestCancelAiRun,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                  child: Text(
                    s['cancel'],
                    style: AppTypography.metaStyle.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.aiCyan,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
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
