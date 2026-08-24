import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../files/editor/file_preview.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/note_widgets.dart';
import '../topic/topic_appearance.dart';
import '../widgets/app_context_menu.dart';
import '../widgets/main_pane_loader.dart';

class ArchiveFilePreview extends StatelessWidget {
  const ArchiveFilePreview({
    super.key,
    required this.state,
    required this.file,
    required this.onUnarchive,
    required this.onDelete,
  });

  final AppState state;
  final AppFile file;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final topic = state.selectedArchiveTopic;
    final accent =
        topic == null ? null : TopicAppearance.accentFor(topic);
    final agentText = state.archiveAgentTextFor(file.id);
    final s = state.strings;

    return NoteCard(
      topicAccent: accent,
      fileId: file.id,
      isMainTopic: topic?.isMain ?? false,
      child: Padding(
        padding: AppSpacing.notePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.fileDisplayName(file.name),
                    style: AppTypography.noteTitleStyle,
                  ),
                ),
                IconButton(
                  tooltip: s['fileMenu'],
                  onPressed: () => _showMenu(context),
                  icon: const AppIcon(AppIcons.more, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: agentText == null
                  ? const MainPaneLoader(compact: true)
                  : SingleChildScrollView(
                      child: FilePreview(agentText: agentText),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final s = state.strings;
    final isRtl = s.isRtl;
    final corner = box.localToGlobal(
      Offset(isRtl ? 0 : box.size.width, 28),
    );
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: corner,
      isRtl: isRtl,
      entries: [
        AppContextMenuItem(value: 'unarchive', label: s['unarchiveFile']),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'delete',
          label: s['delete'],
          destructive: true,
        ),
      ],
    );
    if (value == 'unarchive') onUnarchive();
    if (value == 'delete') onDelete();
  }
}
