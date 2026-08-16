import 'package:flutter/material.dart';

import '../files/editor/read_only_document_view.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import './pending_review_service.dart';

/// What the reviewer decided about one change.
enum ReviewChoice { accept, reject }

/// How a change looks right now.
enum ChangeState { pending, active, accepted, rejected }

/// The change that owns one source line.
class HunkMark {
  const HunkMark({required this.hunkId, required this.op});

  final String hunkId;

  /// `add` | `remove` | `change`
  final String op;
}

/// Map every line of one side to the change that touches it.
///
/// A table row, a task and a list item are each one agent-text line, so a
/// change inside an embed lands on that row alone.
Map<int, HunkMark> hunkMarksByLine(
  List<PendingReviewHunk> hunks, {
  required bool oldSide,
}) {
  final marks = <int, HunkMark>{};
  for (final hunk in hunks) {
    final start = oldSide ? hunk.oldIndex0 : hunk.newIndex0;
    final end = oldSide ? hunk.oldIndexEnd : hunk.newIndexEnd;
    for (var line = start; line < end; line++) {
      marks[line] = HunkMark(hunkId: hunk.id, op: hunk.op);
    }
  }
  return marks;
}

/// The change covering the whole of [lineStart]..[lineEnd], or null.
///
/// Whole-range on purpose: a change on one table row must tint that row, not
/// the embed around it. A change over the fence and its rows covers the whole
/// block, so then the embed is tinted as one.
HunkMark? markForRange(Map<int, HunkMark> marks, int lineStart, int lineEnd) {
  final first = marks[lineStart];
  if (first == null) return null;
  for (var line = lineStart + 1; line <= lineEnd; line++) {
    if (marks[line]?.hunkId != first.hunkId) return null;
  }
  return first;
}

/// Dress one element for its change state. Teal means kept, grey means dropped;
/// removals stay amber-brown. No green, no red — see the UI AREA.
LineDecoration decorationForChange({
  required HunkMark mark,
  required ChangeState state,
  required bool oldSide,
  GlobalKey? anchorKey,
  VoidCallback? onTap,
  InlineSpan Function(String text)? spanFor,
}) {
  final hue = switch (mark.op) {
    'add' => AppColors.primary,
    'remove' => AppColors.destructive,
    _ => oldSide ? AppColors.destructive : AppColors.primary,
  };

  return switch (state) {
    ChangeState.pending => LineDecoration(
        tint: hue.withValues(alpha: 0.07),
        anchorKey: anchorKey,
        onTap: onTap,
        spanFor: spanFor,
      ),
    ChangeState.active => LineDecoration(
        tint: hue.withValues(alpha: 0.14),
        barColor: AppColors.primary,
        anchorKey: anchorKey,
        onTap: onTap,
        spanFor: spanFor,
      ),
    ChangeState.accepted => LineDecoration(
        tint: AppColors.primary.withValues(alpha: 0.10),
        mark: AppIcons.check,
        markColor: AppColors.primary,
        anchorKey: anchorKey,
        onTap: onTap,
        spanFor: spanFor,
      ),
    ChangeState.rejected => LineDecoration(
        tint: AppColors.textHint.withValues(alpha: 0.08),
        mark: AppIcons.close,
        markColor: AppColors.textHint,
        opacity: 0.45,
        anchorKey: anchorKey,
        onTap: onTap,
        spanFor: spanFor,
      ),
  };
}

ChangeState changeStateFor({
  required String hunkId,
  required String? activeHunkId,
  required Map<String, ReviewChoice> choices,
}) {
  final choice = choices[hunkId];
  if (choice == ReviewChoice.accept) return ChangeState.accepted;
  if (choice == ReviewChoice.reject) return ChangeState.rejected;
  return hunkId == activeHunkId ? ChangeState.active : ChangeState.pending;
}

/// The change the bubble should move to after [fromId] is decided: the next
/// undecided one below it, wrapping to the first undecided above.
String? nextUndecidedHunkId(
  List<PendingReviewHunk> hunks,
  Map<String, ReviewChoice> choices, {
  String? fromId,
}) {
  if (hunks.isEmpty) return null;
  final startAt = fromId == null
      ? 0
      : hunks.indexWhere((h) => h.id == fromId) + 1;
  for (var i = startAt.clamp(0, hunks.length); i < hunks.length; i++) {
    if (!choices.containsKey(hunks[i].id)) return hunks[i].id;
  }
  for (var i = 0; i < startAt.clamp(0, hunks.length); i++) {
    if (!choices.containsKey(hunks[i].id)) return hunks[i].id;
  }
  return null;
}
