import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../files/data/app_file.dart';
import '../files/data/topic.dart';
import '../files/editor/document_pane.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_typography.dart';
import '../ui/dialog_metrics.dart';
import '../ui/glass_surface.dart';
import '../ux/topic/topic_appearance.dart';

/// Host the real file editor so an automation step can save a snippet.
Future<Map<String, dynamic>?> showFillFileSnippetDialog({
  required BuildContext context,
  required AppState state,
  required Topic topic,
  Map<String, dynamic>? existing,
}) {
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    isDismissible: false,
    builder: (ctx) => _FillFileSnippetDialog(
      state: state,
      topic: topic,
      existing: existing,
    ),
  );
}

class _FillFileSnippetDialog extends StatefulWidget {
  const _FillFileSnippetDialog({
    required this.state,
    required this.topic,
    this.existing,
  });

  final AppState state;
  final Topic topic;
  final Map<String, dynamic>? existing;

  @override
  State<_FillFileSnippetDialog> createState() => _FillFileSnippetDialogState();
}

class _FillFileSnippetDialogState extends State<_FillFileSnippetDialog> {
  AppFile? _file;
  Object? _error;
  var _busy = true;
  var _finishing = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _openScratch();
  }

  Future<void> _openScratch() async {
    AppFile? file;
    try {
      file = await state.createScratchFile(
        topicId: widget.topic.id,
        name: state.strings['stepFillFile'],
      );
      final existing = widget.existing;
      if (existing != null &&
          (existing['document_json'] as String? ?? '').trim().isNotEmpty) {
        file = await state.applyFileSnippet(file.id, existing);
      }
      if (!mounted) {
        await state.discardScratchFile(file.id);
        return;
      }
      setState(() {
        _file = file;
        _busy = false;
      });
    } catch (error) {
      if (file != null) await state.discardScratchFile(file.id);
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  Future<void> _finish({required bool save}) async {
    if (_finishing) return;
    _finishing = true;
    Map<String, dynamic>? snapshot;
    final file = _file;
    try {
      if (save && file != null) {
        snapshot = await state.snapshotFileForAutomation(file.id);
      }
    } catch (error) {
      _finishing = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (file != null) await state.discardScratchFile(file.id);
    if (mounted) Navigator.pop(context, snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final height = MediaQuery.sizeOf(context).height * 0.58;
    return AppGlassDialog(
      title: Text(s['stepFillFile']),
      width: AppDialogMetrics.fileEditorWidth,
      scrollable: false,
      actions: [
        TextButton(
          onPressed: _finishing ? null : () => _finish(save: false),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _finishing || _file == null
              ? null
              : () => _finish(save: true),
          child: Text(s['save']),
        ),
      ],
      child: SizedBox(
        height: height,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_busy) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null || _file == null) {
      return Center(
        child: Text(
          _error?.toString() ?? widget.state.strings['automationFailed'],
          style: AppTypography.metaStyle,
          textAlign: TextAlign.center,
        ),
      );
    }
    return DocumentPane(
      topic: widget.topic,
      file: _file!,
      state: state,
      accent: TopicAppearance.accentFor(widget.topic),
      autoOpenPendingReview: false,
      showFileMenu: false,
      onDelete: () => _finish(save: false),
    );
  }
}
