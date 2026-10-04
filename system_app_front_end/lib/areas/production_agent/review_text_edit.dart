import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../files/editor/editor_key_handoff.dart';
import '../files/model/agent_text_blocks.dart';
import 'pending_review_service.dart';

/// Only visible text is editable; object fences and table/chart structure stay
/// on the existing accept/reject path. Keep line positions and list markers.
class ReviewTextEdit {
  const ReviewTextEdit(this.prefix);
  final String prefix;
}

ReviewTextEdit? reviewTextEdit(PendingReview pending, PendingReviewHunk hunk) {
  if (hunk.newLines.length != 1) return null;
  final line = hunk.newIndex0;
  final blocks = parseAgentTextBlocks(pending.newAgentText);
  final visible = blocks.any(
    (b) => switch (b) {
      AgentParagraphBlock() => b.lineStart == line,
      AgentHeadingBlock() => b.lineStart == line,
      AgentListBlock() => b.items.any((item) => item.line == line),
      AgentTaskListBlock() => b.tasks.any((task) => task.line == line),
      AgentInfoBlock() =>
        b.titleLine == line || b.bodyLines.any((body) => body.line == line),
      _ => false,
    },
  );
  if (!visible) return null;
  final text = hunk.newLines.single;
  if (RegExp(r'^\s*\[/?[A-Z_]+(?:\s|\])').hasMatch(text)) return null;
  final prefix =
      RegExp(
        r'^\s*(?:#{1,6}\s+|-\s*\[[ xX]\]\s*|[-*]\s+|\d+[.)]\s+)',
      ).firstMatch(text)?.group(0) ??
      '';
  return ReviewTextEdit(prefix);
}

class ReviewTextEditDialog extends StatefulWidget {
  const ReviewTextEditDialog({
    super.key,
    required this.edit,
    required this.initialLine,
    required this.strings,
  });
  final ReviewTextEdit edit;
  final String initialLine;
  final AppStrings strings;

  @override
  State<ReviewTextEditDialog> createState() => _ReviewTextEditDialogState();
}

class _ReviewTextEditDialogState extends State<ReviewTextEditDialog> {
  late final _controller = TextEditingController(
    text: widget.initialLine.substring(widget.edit.prefix.length),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(String? text) => runWhenKeyboardIdle(() {
    if (mounted) Navigator.pop(context, text);
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Directionality(
      textDirection: s.textDirection,
      child: AlertDialog(
        title: Text('${s['edit']} — ${s['reviewPaneSuggested']}'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const ValueKey('review-rewrite-field'),
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _close(null), child: Text(s['cancel'])),
          FilledButton(
            onPressed: () => _close('${widget.edit.prefix}${_controller.text}'),
            child: Text(s['reviewAccept']),
          ),
        ],
      ),
    );
  }
}
