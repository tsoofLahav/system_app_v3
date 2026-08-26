import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/dialog_metrics.dart';
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

bool infoHasName(String title, {String body = ''}) {
  final t = title.trim();
  if (t.isEmpty) return false;
  // Empty infos used to arrive from the graph as the type name "Info".
  if (t.toLowerCase() == 'info' && body.trim().isEmpty) return false;
  return true;
}

bool infoNameMatches(String title, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return title.toLowerCase().contains(q);
}

List<ObjectGraphNode> namedInfoNodes(
  Iterable<ObjectGraphNode> nodes, {
  Set<int> excludeObjectIds = const {},
  String query = '',
}) {
  final named = [
    for (final n in nodes)
      if (n.type == 'info' &&
          !excludeObjectIds.contains(n.objectId) &&
          infoHasName(n.title, body: n.body) &&
          infoNameMatches(n.title, query))
        n,
  ];
  named.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return named;
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
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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
        if (widget.infoOnly && !infoHasName(n.title, body: n.body)) continue;
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
        final title = e.type == 'info'
            ? (e.information?['title'] as String? ?? '').trim()
            : e.taskListTitle.trim().isNotEmpty
                ? e.taskListTitle
                : e.type;
        final body = e.type == 'info'
            ? (e.information?['body'] as String? ?? '')
            : '';
        if (widget.infoOnly && !infoHasName(title, body: body)) continue;
        seen.add(e.id);
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

  List<ConnectionPick> get _visible {
    return [
      for (final o in _options)
        if (infoNameMatches(o.title, _query.text)) o,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final visible = _visible;
    return AppAdaptiveDialogShell(
      title: Text(s['addConnection']),
      width: AppDialogMetrics.wideWidth,
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
          : _InfoPickBody(
              searchLabel: s['searchInfo'],
              emptyLabel:
                  widget.infoOnly ? s['noInfoObjects'] : s['noObjectsToConnect'],
              query: _query,
              itemCount: visible.length,
              onActivate: (i) => Navigator.pop(context, visible[i]),
              itemBuilder: (context, i) {
                final o = visible[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.title, style: AppTypography.noteBodyStyle),
                      if (!widget.infoOnly)
                        Text(o.type, style: AppTypography.metaStyle),
                    ],
                  ),
                );
              },
              onQueryChanged: () => setState(() {}),
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
  return showAppDialog<ObjectGraphNode>(
    context: context,
    builder: (_) => _PickInfoObjectDialog(
      state: state,
      excludeObjectIds: excludeObjectIds,
    ),
  );
}

class _PickInfoObjectDialog extends StatefulWidget {
  const _PickInfoObjectDialog({
    required this.state,
    required this.excludeObjectIds,
  });

  final AppState state;
  final Set<int> excludeObjectIds;

  @override
  State<_PickInfoObjectDialog> createState() => _PickInfoObjectDialogState();
}

class _PickInfoObjectDialogState extends State<_PickInfoObjectDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ObjectGraphNode> get _nodes => namedInfoNodes(
        widget.state.objectGraph?.nodes ?? const [],
        excludeObjectIds: widget.excludeObjectIds,
        query: _query.text,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final nodes = _nodes;
    return AppAdaptiveDialogShell(
      title: Text(s['connectInfo']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
      child: _InfoPickBody(
        searchLabel: s['searchInfo'],
        emptyLabel: s['noInfoObjects'],
        query: _query,
        itemCount: nodes.length,
        onActivate: (i) => Navigator.pop(context, nodes[i]),
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(nodes[i].title, style: AppTypography.noteBodyStyle),
        ),
        onQueryChanged: () => setState(() {}),
      ),
    );
  }
}

class _InfoPickBody extends StatelessWidget {
  const _InfoPickBody({
    required this.searchLabel,
    required this.emptyLabel,
    required this.query,
    required this.itemCount,
    required this.onActivate,
    required this.itemBuilder,
    required this.onQueryChanged,
  });

  final String searchLabel;
  final String emptyLabel;
  final TextEditingController query;
  final int itemCount;
  final ValueChanged<int> onActivate;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final VoidCallback onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppDialogField(
          label: searchLabel,
          child: TextField(
            controller: query,
            autofocus: true,
            style: AppTypography.noteBodyStyle.copyWith(fontSize: 12),
            decoration: DialogFieldStyle.decoration(),
            onChanged: (_) => onQueryChanged(),
            onSubmitted: (_) {
              if (itemCount > 0) onActivate(0);
            },
          ),
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        if (itemCount == 0)
          Text(emptyLabel, style: AppTypography.noteBodyStyle)
        else
          DialogChoiceList(
            itemCount: itemCount,
            maxHeight: 240,
            autofocus: false,
            onActivate: onActivate,
            itemBuilder: (context, i, _) => itemBuilder(context, i),
          ),
      ],
    );
  }
}
