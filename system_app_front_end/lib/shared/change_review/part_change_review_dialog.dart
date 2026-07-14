import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/change_set.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import 'change_review_dialog.dart';

Future<Map<String, bool>?> showPartChangeReviewDialog({
  required BuildContext context,
  required AppStrings strings,
  required List<PartChangeEntry> parts,
  String? title,
}) {
  return showDialog<Map<String, bool>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PartChangeReviewDialog(
      strings: strings,
      parts: parts,
      title: title,
    ),
  );
}

class PartChangeReviewDialog extends StatefulWidget {
  const PartChangeReviewDialog({
    super.key,
    required this.strings,
    required this.parts,
    this.title,
    this.embedded = false,
    this.onComplete,
    this.onCancel,
  });

  final AppStrings strings;
  final List<PartChangeEntry> parts;
  final String? title;
  final bool embedded;
  final ValueChanged<Map<String, bool>>? onComplete;
  final VoidCallback? onCancel;

  @override
  State<PartChangeReviewDialog> createState() => _PartChangeReviewDialogState();
}

class _PartChangeReviewDialogState extends State<PartChangeReviewDialog> {
  late int _partIndex;
  final _allDecisions = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _partIndex = 0;
  }

  PartChangeEntry get _currentPart => widget.parts[_partIndex];

  void _onPartComplete(Map<String, bool> decisions) {
    _allDecisions.addAll(decisions);
    if (_partIndex >= widget.parts.length - 1) {
      if (widget.embedded) {
        widget.onComplete?.call(Map<String, bool>.from(_allDecisions));
      } else {
        Navigator.pop(context, Map<String, bool>.from(_allDecisions));
      }
      return;
    }
    setState(() => _partIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final part = _currentPart;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s['reviewPart']}: ${part.partName}',
          style: AppTypography.noteTitleStyle,
        ),
        if (part.isNew)
          Text(
            s['reviewNewPart'],
            style: AppTypography.metaStyle,
          ),
        Text(
          '${_partIndex + 1} / ${widget.parts.length}',
          style: AppTypography.metaStyle,
        ),
        const SizedBox(height: 8),
      ],
    );

    final review = ChangeReviewDialog(
      key: ValueKey('part-review-${part.partId ?? part.partName}-$_partIndex'),
      strings: widget.strings,
      changeSet: part.toDocumentChangeSet(),
      embedded: true,
      onComplete: _onPartComplete,
      onCancel: widget.onCancel,
    );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(child: review),
        ],
      );
    }

    return AppGlassDialog(
      title: Text(widget.title ?? s['reviewProjectUpdate']),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel?.call();
            Navigator.pop(context);
          },
          child: Text(s['cancel']),
        ),
      ],
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Expanded(child: review),
          ],
        ),
      ),
    );
  }
}
