import 'package:flutter/material.dart';

import '../model/agent_text_blocks.dart';
import './read_only_document_view.dart';

/// How the shared read-only file is shown.
enum FilePreviewMode {
  /// Full document; the parent owns scrolling (archive, review).
  full,

  /// Window onto the top of the file. No scroll, no pointer — overlay cards.
  clipped,
}

/// The file as the user reads it: visual structure, no editing, no markers.
///
/// Feed [blocks] when the agent text is already parsed (the review dialog),
/// or [agentText] from `GET /files/:id/agent-text`. Never pass editor/marker
/// text — leftover fences render as a quiet rule, not as `[INFO id=…]`.
class FilePreview extends StatelessWidget {
  const FilePreview({
    super.key,
    this.blocks,
    this.agentText,
    this.decorate,
    this.mode = FilePreviewMode.full,
    this.placeholder,
  });

  final List<AgentBlock>? blocks;
  final String? agentText;
  final LineDecorator? decorate;
  final FilePreviewMode mode;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (blocks == null && agentText == null) {
      return placeholder ??
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }
    final view = ReadOnlyDocumentView(
      blocks: blocks ?? parseAgentTextBlocks(agentText ?? ''),
      decorate: decorate ?? _plain,
    );
    if (mode == FilePreviewMode.full) return view;
    return IgnorePointer(
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: view,
        ),
      ),
    );
  }
}

LineDecoration _plain(int lineStart, int lineEnd) => LineDecoration.none;

/// Loads agent text once and draws [FilePreview]. Same file id shares one fetch.
class FilePreviewLoader extends StatefulWidget {
  const FilePreviewLoader({
    super.key,
    required this.fileId,
    required this.loadAgentText,
    this.mode = FilePreviewMode.clipped,
    this.placeholder,
  });

  final int fileId;
  final Future<String> Function(int fileId) loadAgentText;
  final FilePreviewMode mode;
  final Widget? placeholder;

  @override
  State<FilePreviewLoader> createState() => _FilePreviewLoaderState();
}

class _FilePreviewLoaderState extends State<FilePreviewLoader> {
  static final _inflight = <int, Future<String>>{};

  String? _agentText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FilePreviewLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _agentText = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.fileId;
    final future = _inflight.putIfAbsent(id, () async {
      try {
        return await widget.loadAgentText(id);
      } finally {
        _inflight.remove(id);
      }
    });
    final text = await future;
    if (!mounted || widget.fileId != id) return;
    setState(() => _agentText = text);
  }

  @override
  Widget build(BuildContext context) {
    return FilePreview(
      agentText: _agentText,
      mode: widget.mode,
      placeholder: widget.placeholder,
    );
  }
}
