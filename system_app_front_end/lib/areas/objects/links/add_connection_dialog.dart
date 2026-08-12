import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_typography.dart';
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
}) {
  return showAppDialog<ConnectionPick>(
    context: context,
    builder: (_) => _AddConnectionDialog(state: state, source: source),
  );
}

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({
    required this.state,
    required this.source,
  });

  final AppState state;
  final ObjectEmbed source;

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
    // Regular + through-text connections only target infos.
    if (graph != null) {
      for (final n in graph.nodes) {
        if (n.type != 'info') continue;
        if (seen.contains(n.objectId)) continue;
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
        if (e.type != 'info') continue;
        if (seen.contains(e.id)) continue;
        seen.add(e.id);
        final title = (e.information?['title'] as String? ?? '').trim();
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
              ? Text(s['noObjectsToConnect'], style: AppTypography.noteBodyStyle)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in _options)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(o.title, style: AppTypography.noteBodyStyle),
                          subtitle: Text(
                            o.type,
                            style: AppTypography.metaStyle,
                          ),
                          onTap: () => Navigator.pop(context, o),
                        ),
                    ],
                  ),
                ),
    );
  }
}

Future<ObjectGraphNode?> showPickInfoObjectDialog({
  required BuildContext context,
  required AppState state,
}) async {
  await state.loadObjectGraph();
  if (!context.mounted) return null;
  final nodes = [
    for (final n in state.objectGraph?.nodes ?? const <ObjectGraphNode>[])
      if (n.type == 'info') n,
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
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final n in nodes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(n.title, style: AppTypography.noteBodyStyle),
                      onTap: () => Navigator.pop(context, n),
                    ),
                ],
              ),
            ),
    ),
  );
}
