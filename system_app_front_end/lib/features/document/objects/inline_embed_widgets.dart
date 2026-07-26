import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/models/object_embed.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_typography.dart';
import '../inline_document_model.dart';
import '../rich_text/formatted_text_field.dart';
import '../rich_text/span_text_editing_controller.dart';

class InlineImageWidget extends StatelessWidget {
  const InlineImageWidget({
    super.key,
    required this.embed,
    required this.onUrlChanged,
  });

  final DocumentEmbed embed;
  final ValueChanged<String> onUrlChanged;

  @override
  Widget build(BuildContext context) {
    final url = embed.url?.trim() ?? '';
    if (url.isEmpty) {
      return SizedBox(
        width: 240,
        height: 120,
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Image URL',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: onUrlChanged,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: embed.width ?? 320,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Text('Image failed to load', style: AppTypography.metaStyle),
      ),
    );
  }
}

class InlineGraphWidget extends StatelessWidget {
  const InlineGraphWidget({super.key, required this.embed});

  final DocumentEmbed embed;

  @override
  Widget build(BuildContext context) {
    final labels = embed.labels;
    final values = embed.values;
    if (labels.isEmpty || values.isEmpty) {
      return Text('[graph]', style: AppTypography.metaStyle);
    }
    final maxVal = values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length && i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[i] / maxVal,
                          widthFactor: 0.6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(labels[i], style: AppTypography.metaStyle, maxLines: 1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InlineInfoWidget extends StatefulWidget {
  const InlineInfoWidget({
    super.key,
    required this.embed,
    required this.state,
    required this.onRefresh,
  });

  final ObjectEmbed embed;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  State<InlineInfoWidget> createState() => _InlineInfoWidgetState();
}

class _InlineInfoWidgetState extends State<InlineInfoWidget> {
  late TextEditingController _titleController;
  late SpanTextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    final info = widget.embed.information ?? const {};
    _titleController = TextEditingController(text: info['title'] as String? ?? '');
    final meta = info['metadata'];
    final spans = meta is Map ? meta['spans'] : null;
    _bodyController = SpanTextEditingController(
      text: info['body'] as String? ?? '',
      spans: spans is List
          ? [for (final s in spans) if (s is Map) Map<String, dynamic>.from(s)]
          : const [],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.state.updateInfoObject(
      widget.embed,
      title: _titleController.text,
      body: _bodyController.text,
      spans: _bodyController.spans,
    );
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: AppColors.detailsBlockDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            style: AppTypography.noteTitleStyle,
            decoration: const InputDecoration(
              hintText: 'Info title',
              border: InputBorder.none,
              isDense: true,
            ),
            onEditingComplete: _save,
          ),
          FormattedTextField(
            controller: _bodyController,
            style: AppTypography.noteBodyStyle,
            maxLines: null,
            onChanged: (_) => _save(),
          ),
        ],
      ),
    );
  }
}
