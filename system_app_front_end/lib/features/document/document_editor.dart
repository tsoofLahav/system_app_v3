import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/object_embed.dart';
import '../../design_system/app_typography.dart';
import 'document_codec.dart';
import 'document_model.dart';
import 'nodes/flow_node_widgets.dart';
import 'nodes/paragraph_node_widget.dart';
import 'objects/document_object_widgets.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.file,
    required this.state,
    required this.embeds,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  late RichDocument _doc;
  var _dirty = false;
  var _saveScheduled = false;

  @override
  void initState() {
    super.initState();
    _doc = DocumentCodec.parse(widget.file.body);
    if (_doc.nodes.isEmpty) {
      _doc = _doc.copyWith(
        nodes: [ParagraphNode(id: DocumentCodec.newNodeId(), text: '')],
      );
    }
  }

  @override
  void didUpdateWidget(DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        (!_dirty && oldWidget.file.body != widget.file.body)) {
      _doc = DocumentCodec.parse(widget.file.body);
      _dirty = false;
    }
  }

  ObjectEmbed? _embedForObjectId(int objectId) {
    for (final embed in widget.embeds) {
      if (embed.id == objectId) return embed;
    }
    return null;
  }

  void _updateNode(int index, DocumentNode node) {
    final nodes = List<DocumentNode>.from(_doc.nodes);
    nodes[index] = node;
    setState(() {
      _doc = _doc.copyWith(nodes: nodes);
      _dirty = true;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      _saveScheduled = false;
      await _saveBody();
    });
  }

  Future<void> _saveBody() async {
    if (!_dirty) return;
    await widget.state.updateFile(
      widget.file,
      {'body': DocumentCodec.serialize(_doc)},
    );
    _dirty = false;
  }

  void _insertNode(DocumentNode node, {int? afterIndex}) {
    final nodes = List<DocumentNode>.from(_doc.nodes);
    final index = afterIndex == null ? nodes.length : afterIndex + 1;
    nodes.insert(index, node);
    setState(() {
      _doc = _doc.copyWith(nodes: nodes);
      _dirty = true;
    });
    _scheduleSave();
  }

  Future<void> _insertObject(String type) async {
    final embed = await widget.state.createObjectInDocument(widget.file, type: type);
    _insertNode(
      ObjectNode(
        id: DocumentCodec.newNodeId(),
        objectType: type,
        objectId: embed.id,
      ),
    );
    await widget.state.loadEmbedsForFile(widget.file.id);
    setState(() {});
  }

  Future<void> _refreshEmbeds() async {
    await widget.state.loadEmbedsForFile(widget.file.id);
    setState(() {});
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final nodes = List<DocumentNode>.from(_doc.nodes);
    final item = nodes.removeAt(oldIndex);
    nodes.insert(newIndex, item);
    setState(() {
      _doc = _doc.copyWith(nodes: nodes);
      _dirty = true;
    });
    await _saveBody();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _doc.nodes.length,
          onReorder: _onReorder,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) {
            final node = _doc.nodes[index];
            return ReorderableDragStartListener(
              key: ValueKey(node.id),
              index: index,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8, right: 4),
                    child: Icon(Icons.drag_indicator, size: 18),
                  ),
                  Expanded(child: _buildNode(index, node)),
                ],
              ),
            );
          },
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => _insertNode(
                ParagraphNode(id: DocumentCodec.newNodeId(), text: ''),
              ),
              icon: const Icon(Icons.notes, size: 16),
              label: const Text('Paragraph'),
            ),
            TextButton.icon(
              onPressed: () => _insertNode(
                TableNode(id: DocumentCodec.newNodeId(), rows: [['', '']]),
              ),
              icon: const Icon(Icons.table_chart, size: 16),
              label: const Text('Table'),
            ),
            TextButton.icon(
              onPressed: () => _insertNode(
                ListNode(id: DocumentCodec.newNodeId(), items: ['']),
              ),
              icon: const Icon(Icons.format_list_bulleted, size: 16),
              label: const Text('List'),
            ),
            TextButton.icon(
              onPressed: () => _insertNode(
                ImageNode(id: DocumentCodec.newNodeId(), url: ''),
              ),
              icon: const Icon(Icons.image, size: 16),
              label: const Text('Image'),
            ),
            TextButton.icon(
              onPressed: () => _insertNode(
                GraphNode(
                  id: DocumentCodec.newNodeId(),
                  labels: ['A'],
                  values: [1],
                ),
              ),
              icon: const Icon(Icons.show_chart, size: 16),
              label: const Text('Graph'),
            ),
            TextButton.icon(
              onPressed: () => _insertObject('task_list'),
              icon: const Icon(Icons.checklist, size: 16),
              label: Text(widget.state.strings['addTask'] ?? 'Task list'),
            ),
            TextButton.icon(
              onPressed: () => _insertObject('info'),
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Info'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNode(int index, DocumentNode node) {
    switch (node) {
      case ParagraphNode():
        return ParagraphNodeWidget(
          node: node,
          state: widget.state,
          onChanged: (n) => _updateNode(index, n),
          onBackspaceAtStart: index > 0
              ? () {
                  // merge with previous paragraph if empty
                  if (node.text.isEmpty && index > 0) {
                    final nodes = List<DocumentNode>.from(_doc.nodes);
                    nodes.removeAt(index);
                    setState(() {
                      _doc = _doc.copyWith(nodes: nodes);
                      _dirty = true;
                    });
                    _scheduleSave();
                  }
                }
              : null,
        );
      case TableNode():
        return TableNodeWidget(
          node: node,
          onChanged: (n) => _updateNode(index, n),
        );
      case ListNode():
        return ListNodeWidget(
          node: node,
          onChanged: (n) => _updateNode(index, n),
        );
      case ImageNode():
        return ImageNodeWidget(
          node: node,
          onChanged: (n) => _updateNode(index, n),
        );
      case GraphNode():
        return GraphNodeWidget(
          node: node,
          onChanged: (n) => _updateNode(index, n),
        );
      case ObjectNode():
        final embed = _embedForObjectId(node.objectId);
        if (embed == null) {
          return Text('[${node.objectType} #${node.objectId}]',
              style: AppTypography.metaStyle);
        }
        if (node.objectType == 'task_list') {
          return TaskListObjectWidget(
            node: node,
            embed: embed,
            file: widget.file,
            state: widget.state,
            onRefresh: _refreshEmbeds,
          );
        }
        return InfoObjectWidget(
          node: node,
          embed: embed,
          state: widget.state,
          onRefresh: _refreshEmbeds,
        );
    }
  }
}
