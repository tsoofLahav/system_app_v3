import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/dialog_metrics.dart';
import '../../ux/dialogs/dialog_choice_list.dart';
import '../data/object_embed.dart';
import '../data/object_service.dart';
import './info_pick_rank.dart';

/// Result of ⌘L / Connect info: an info, or **Without** (clear that span).
class InfoConnectionPick {
  const InfoConnectionPick._({this.node, this.clear = false});

  const InfoConnectionPick.none() : this._(clear: true);

  const InfoConnectionPick.info(ObjectGraphNode this.node) : clear = false;

  final ObjectGraphNode? node;
  final bool clear;

  int? get objectId => node?.objectId;
}

class ConnectionPick {
  const ConnectionPick({
    required this.objectId,
    required this.title,
    required this.type,
    this.topicId,
  });

  final int objectId;
  final String title;
  final String type;
  final int? topicId;
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
  String similarTo = '',
  int? topicId,
}) {
  final named = [
    for (final n in nodes)
      if (n.type == 'info' &&
          !excludeObjectIds.contains(n.objectId) &&
          infoHasName(n.title, body: n.body))
        n,
  ];
  return rankInfoPicks(
    items: named,
    titleOf: (n) => n.title,
    topicOf: (n) => n.topicId,
    query: query,
    similarTo: similarTo,
    topicId: topicId,
  );
}

int? topicIdForFile(AppState state, int fileId) {
  final cached = state.fileById(fileId);
  if (cached != null) return cached.topicId;
  final node = state.objectGraph?.nodes
      .where((n) => n.fileId == fileId && n.topicId != null)
      .firstOrNull;
  return node?.topicId;
}

int? topicIdForHost(
  AppState state, {
  ObjectEmbed? host,
  int? fileId,
  int? taskId,
}) {
  if (taskId != null) {
    final topic = state.tasksById[taskId]?.topicId;
    if (topic != null) return topic;
  }
  if (host != null) {
    final fromGraph = state.objectGraph?.nodes
        .where((n) => n.objectId == host.id)
        .firstOrNull
        ?.topicId;
    if (fromGraph != null) return fromGraph;
  }
  final fid = fileId ?? host?.fileId;
  if (fid == null) return null;
  return topicIdForFile(state, fid);
}

Future<ConnectionPick?> showAddConnectionDialog({
  required BuildContext context,
  required AppState state,
  required ObjectEmbed source,
  bool infoOnly = true,
  String similarTo = '',
}) {
  return showAppDialog<ConnectionPick>(
    context: context,
    builder: (_) => _AddConnectionDialog(
      state: state,
      source: source,
      infoOnly: infoOnly,
      similarTo: similarTo,
    ),
  );
}

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({
    required this.state,
    required this.source,
    this.infoOnly = true,
    this.similarTo = '',
  });

  final AppState state;
  final ObjectEmbed source;
  final bool infoOnly;
  final String similarTo;

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
            topicId: n.topicId,
          ),
        );
      }
    }

    for (final entry in widget.state.embedsByFileId.entries) {
      for (final e in entry.value) {
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
            topicId: topicIdForFile(widget.state, entry.key),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _options
        ..clear()
        ..addAll(options);
      _loading = false;
    });
  }

  List<ConnectionPick> get _visible {
    return rankInfoPicks(
      items: _options,
      titleOf: (o) => o.title,
      topicOf: (o) => o.topicId,
      query: _query.text,
      similarTo: widget.similarTo,
      topicId: topicIdForHost(widget.state, host: widget.source),
    );
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
              emptyLabel: widget.infoOnly
                  ? s['noInfoObjects']
                  : s['noObjectsToConnect'],
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

Future<InfoConnectionPick?> showPickInfoObjectDialog({
  required BuildContext context,
  required AppState state,
  Set<int> excludeObjectIds = const {},
  String similarTo = '',
  int? topicId,
}) async {
  await state.loadObjectGraph();
  if (!context.mounted) return null;
  return showAppDialog<InfoConnectionPick>(
    context: context,
    builder: (_) => _PickInfoObjectDialog(
      state: state,
      excludeObjectIds: excludeObjectIds,
      similarTo: similarTo,
      topicId: topicId,
    ),
  );
}

class _PickInfoObjectDialog extends StatefulWidget {
  const _PickInfoObjectDialog({
    required this.state,
    required this.excludeObjectIds,
    this.similarTo = '',
    this.topicId,
  });

  final AppState state;
  final Set<int> excludeObjectIds;
  final String similarTo;
  final int? topicId;

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
    similarTo: widget.similarTo,
    topicId: widget.topicId,
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
        leadingLabel: s['connectWithout'],
        onLeading: () =>
            Navigator.pop(context, const InfoConnectionPick.none()),
        itemCount: nodes.length,
        onActivate: (i) =>
            Navigator.pop(context, InfoConnectionPick.info(nodes[i])),
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
    this.leadingLabel,
    this.onLeading,
  });

  final String searchLabel;
  final String emptyLabel;
  final TextEditingController query;
  final int itemCount;
  final ValueChanged<int> onActivate;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final VoidCallback onQueryChanged;
  final String? leadingLabel;
  final VoidCallback? onLeading;

  int get _leadingCount =>
      leadingLabel != null && onLeading != null ? 1 : 0;

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
        if (itemCount + _leadingCount == 0)
          Text(emptyLabel, style: AppTypography.noteBodyStyle)
        else
          DialogChoiceList(
            itemCount: itemCount + _leadingCount,
            maxHeight: 240,
            autofocus: false,
            onActivate: (i) {
              if (_leadingCount == 1 && i == 0) {
                onLeading!();
                return;
              }
              onActivate(i - _leadingCount);
            },
            itemBuilder: (context, i, _) {
              if (_leadingCount == 1 && i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    leadingLabel!,
                    style: AppTypography.noteBodyStyle,
                  ),
                );
              }
              return itemBuilder(context, i - _leadingCount);
            },
          ),
      ],
    );
  }
}
