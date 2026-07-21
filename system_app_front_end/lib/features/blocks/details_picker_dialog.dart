import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/details_block_summary.dart';
import '../../core/models/task.dart';

class DetailsPickerDialog extends StatefulWidget {
  const DetailsPickerDialog({
    super.key,
    required this.strings,
    required this.items,
    required this.taskTitle,
    this.initialBlockId,
  });

  final AppStrings strings;
  final List<DetailsBlockSummary> items;
  final String taskTitle;
  final int? initialBlockId;

  static Future<int?> show({
    required BuildContext context,
    required AppState state,
    required Task task,
    required List<DetailsBlockSummary> items,
    int? suggestedBlockId,
  }) {
    return showDialog<int?>(
      context: context,
      builder: (context) => DetailsPickerDialog(
        strings: state.strings,
        items: items,
        taskTitle: task.title,
        initialBlockId: suggestedBlockId,
      ),
    );
  }

  @override
  State<DetailsPickerDialog> createState() => _DetailsPickerDialogState();
}

class _DetailsPickerDialogState extends State<DetailsPickerDialog> {
  int? _selectedBlockId;

  @override
  void initState() {
    super.initState();
    _selectedBlockId = widget.initialBlockId;
    if (_selectedBlockId == null && widget.items.isNotEmpty) {
      _selectedBlockId = widget.items.first.blockId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(strings['attachDetailsTitle']),
      content: SizedBox(
        width: 420,
        child: widget.items.isEmpty
            ? Text(strings['noDetailsInTopic'])
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings['attachDetailsPrompt'].replaceAll(
                      '{task}',
                      widget.taskTitle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        return RadioListTile<int>(
                          value: item.blockId,
                          groupValue: _selectedBlockId,
                          onChanged: (value) =>
                              setState(() => _selectedBlockId = value),
                          title: Text(
                            item.title.isEmpty
                                ? strings['detailsUntitled']
                                : item.title,
                          ),
                          subtitle: Text(
                            '${item.fileName}${item.textPreview.isEmpty ? '' : ' · ${item.textPreview}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings['cancel']),
        ),
        if (widget.items.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(strings['detachDetails']),
          ),
        if (widget.items.isNotEmpty)
          FilledButton(
            onPressed: _selectedBlockId == null
                ? null
                : () => Navigator.pop(context, _selectedBlockId),
            child: Text(strings['attachDetailsConfirm']),
          ),
      ],
    );
  }
}
