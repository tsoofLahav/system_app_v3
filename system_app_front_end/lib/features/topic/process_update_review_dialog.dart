import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/ai_proposal.dart';
import '../../core/models/change_set.dart';
import '../../shared/change_review/change_review_dialog.dart';

Future<void> showProcessUpdateReviewDialog({
  required BuildContext context,
  required AppState state,
  required AiProposal proposal,
}) async {
  final raw = proposal.payload['change_set'];
  if (raw is! Map<String, dynamic>) return;

  final decisions = await showChangeReviewDialog(
    context: context,
    strings: state.strings,
    changeSet: ChangeSet.fromJson(raw),
    title: state.strings['processUpdateReview'],
  );
  if (decisions == null) return;

  await state.finalizeProcessUpdate(proposal, decisions);
}
