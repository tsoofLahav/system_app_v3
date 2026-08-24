import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_typography.dart';
import '../../ux/dialogs/dialog_choice_list.dart';
import '../data/object_embed.dart';
import '../data/object_service.dart';

class ConnectionPick {
  const ConnectionPick({
    required this.objectId,
    required this.title,
    required this.type,
  });

  final int objectId;
  final String title;
  final String type;
}

Future<ConnectionPick?> showAddConnectionDialog({
  required BuildContext context,
  required AppState state,
  required ObjectEmbed source,
  bool infoOnly = true,
}) {
  return showAppDialog<ConnectionPick>(
    context: context,
    builder: (_) => _AddConnectionDialog(
      state: state,
      source: source,
      infoOnly: infoOnly,
    ),
  );
}

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({
    required this.state,
    required this.source,
    this.infoOnly = true,
  });

  final AppState state;
  final ObjectEmbed source;
  final bool infoOnly;

  @override
  State<_AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<_AddConnectionDialog> {
  var _loading = true;
  final _options = <ConnectionPick>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.state.loadObjectGraph();
    final seen = <int>{widget.source.id};
    final options = <ConnectionPick>[];

    final graph = widget.state.objectGraph;
    if (graph != null) {
      for (final n in graph.nodes) {
        if (seen.contains(n.objectId)) continue;
        if (widget.infoOnly && n.type != 'info') continue;
        seen.add(n.objectId);
        options.add(
          ConnectionPick(
            objectId: n.objectId,
            title: n.title,
            type: n.type,
          ),
        );
      }
    }

    for (final embeds in widget.state.embedsByFileId.values) {
      for (final e in embeds) {
        if (seen.contains(e.id)) continue;
        if (widget.infoOnly && e.type != 'info') continue;
        seen.add(e.id);
        final title = e.type == 'info'
            ? (e.information?['title'] as String? ?? '').trim()
            : e.taskListTitle.trim().isNotEmpty
                ? e.taskListTitle
                : e.type;
        options.add(
          ConnectionPick(
            objectId: e.id,
            title: title.isEmpty ? e.type : title,
            type: e.type,
          ),
        );
      }
    }

    options.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _options
        ..clear()
        ..addAll(options);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['addConnection']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
      child: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _options.isEmpty
              ? Text(
                  widget.infoOnly ? s['noInfoObjects'] : s['noObjectsToConnect'],
                  style: AppTypography.noteBodyStyle,
                )
              : DialogChoiceList(
                  itemCount: _options.length,
                  onActivate: (i) => Navigator.pop(context, _options[i]),
                  itemBuilder: (context, i, _) {
                    final o = _options[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.title, style: AppTypography.noteBodyStyle),
                          Text(o.type, style: AppTypography.metaStyle),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

Future<ObjectGraphNode?> showPickInfoObjectDialog({
  required BuildContext context,
  required AppState state,
  Set<int> excludeObjectIds = const {},
}) async {
  await state.loadObjectGraph();
  if (!context.mounted) return null;
  final nodes = [
    for (final n in state.objectGraph?.nodes ?? const <ObjectGraphNode>[])
      if (!excludeObjectIds.contains(n.objectId)) n,
  ];
  return showAppDialog<ObjectGraphNode>(
    context: context,
    builder: (_) => AppAdaptiveDialogShell(
      title: Text(state.strings['connectInfo']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(state.strings['cancel']),
        ),
      ],
      child: nodes.isEmpty
          ? Text(
              state.strings['noInfoObjects'],
              style: AppTypography.noteBodyStyle,
            )
          : DialogChoiceList(
              itemCount: nodes.length,
              onActivate: (i) => Navigator.pop(context, nodes[i]),
              itemBuilder: (context, i, _) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    nodes[i].title,
                    style: AppTypography.noteBodyStyle,
                  ),
                );
              },
            ),
    ),
  );
}
