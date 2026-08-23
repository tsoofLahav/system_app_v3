import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../topic/topic_appearance.dart';
import '../widgets/phone_tinted_name_tile.dart';

Future<void> showPhoneFileReorderSheet({
  required BuildContext context,
  required AppState state,
}) async {
  final topic = state.selectedDetail?.topic;
  if (topic == null) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PhoneFileReorderSheet(state: state),
  );
}

class _PhoneFileReorderSheet extends StatefulWidget {
  const _PhoneFileReorderSheet({required this.state});

  final AppState state;

  @override
  State<_PhoneFileReorderSheet> createState() => _PhoneFileReorderSheetState();
}

class _PhoneFileReorderSheetState extends State<_PhoneFileReorderSheet> {
  late List<AppFile> _ordered;
  var _saving = false;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    final detail = _state.selectedDetail!;
    _ordered = List<AppFile>.from(
      _state.orderedFilesFor(detail.topic, detail.files),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final topic = _state.selectedDetail?.topic;
    if (topic == null) return;
    setState(() => _saving = true);
    await _state.reorderTopicFiles(topic, ordered: _ordered);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = _state.strings;
    final topic = _state.selectedDetail?.topic;
    final height = MediaQuery.sizeOf(context).height * 0.86;

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: SizedBox(
        height: height,
        child: GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          tintOpacity: 0.94,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.text.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(s['cancel']),
                    ),
                    Expanded(
                      child: Text(
                        s['arrangeFiles'],
                        textAlign: TextAlign.center,
                        style: AppTypography.noteTitleStyle,
                      ),
                    ),
                    TextButton(
                      onPressed: _saving || _ordered.length < 2 ? null : _save,
                      child: Text(s['arrangeDone']),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _ordered.isEmpty
                    ? Center(
                        child: Text(
                          s['topicNoFiles'],
                          style: AppTypography.metaStyle,
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: _ordered.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final file = _ordered.removeAt(oldIndex);
                            _ordered.insert(newIndex, file);
                          });
                        },
                        itemBuilder: (context, index) {
                          final file = _ordered[index];
                          final paneTopic = topic == null
                              ? null
                              : _state.canvasTopicFor(topic, file);
                          return PhoneTintedNameTile(
                            key: ValueKey(file.id),
                            title: _state.fileDisplayName(file.name),
                            subtitle: '${index + 1} / ${_ordered.length}',
                            fileId: file.id,
                            accent: paneTopic == null
                                ? null
                                : TopicAppearance.accentFor(paneTopic),
                            isMainTopic: paneTopic?.isMain ?? false,
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsetsDirectional.only(start: 8),
                                child: AppIcon(AppIcons.menu, size: 18),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
