import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/ai_proposal.dart';
import '../../core/models/change_set.dart';
import '../../shared/change_review/change_review_dialog.dart';
import '../../shared/change_review/part_change_review_dialog.dart';

Future<AiProposal?> showProjectUpdateReviewDialog({
  required BuildContext context,
  required AppState state,
  required AiProposal proposal,
}) async {
  final raw = proposal.payload['change_set'];
  if (raw is! Map<String, dynamic>) return null;

  final changeSet = ChangeSet.fromJson(raw);
  final Map<String, bool>? decisions;
  if (changeSet.isPartBased) {
    final parts = changeSet.parts ?? const [];
    if (parts.isEmpty) return null;
    decisions = await showPartChangeReviewDialog(
      context: context,
      strings: state.strings,
      parts: parts,
      title: state.strings['projectUpdateReview'],
    );
  } else {
    decisions = await showChangeReviewDialog(
      context: context,
      strings: state.strings,
      changeSet: changeSet,
      title: state.strings['projectUpdateReview'],
    );
  }
  if (decisions == null) return null;

  return state.finalizeProjectUpdate(proposal, decisions);
}
