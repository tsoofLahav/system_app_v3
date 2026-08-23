import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../widgets/app_context_menu.dart';
import '../widgets/main_pane_loader.dart';
import '../widgets/topic_emoji.dart';
import './archive_file_grid.dart';
import './archive_file_preview.dart';

class ArchiveTopicView extends StatefulWidget {
  const ArchiveTopicView({super.key, required this.state});

  final AppState state;

  @override
  State<ArchiveTopicView> createState() => _ArchiveTopicViewState();
}

class _ArchiveTopicViewState extends State<ArchiveTopicView> {
  final _scroll = ScrollController();
  late final TextEditingController _search;
  var _searchOpen = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: state.archiveSearchQuery);
    _scroll.addListener(_onScroll);
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onState() {
    if (_search.text != state.archiveSearchQuery &&
        state.archiveSearchQuery.isEmpty) {
      _search.clear();
      _searchOpen = false;
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter > 280) return;
    unawaitedLoadMore();
  }

  void unawaitedLoadMore() {
    state.loadMoreArchiveContent();
  }

  Future<void> _unarchive(AppFile file) async {
    final s = state.strings;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['unarchiveFileTitle'],
      message: s.unarchiveFileMessage(state.fileDisplayName(file.name)),
      confirmLabel: s['unarchiveFile'],
      cancelLabel: s['cancel'],
    );
    if (!ok || !mounted) return;
    await state.unarchiveFile(file);
  }

  Future<void> _delete(AppFile file) async {
    final s = state.strings;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['deleteFileTitle'],
      message: s.deleteFileMessage(state.fileDisplayName(file.name)),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!ok || !mounted) return;
    await state.deleteArchiveFile(file);
  }

  Future<void> _fileMenu(AppFile file, Offset globalPosition) async {
    final s = state.strings;
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      isRtl: s.isRtl,
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
    if (!mounted || value == null) return;
    if (value == 'unarchive') await _unarchive(file);
    if (value == 'delete') await _delete(file);
  }

  @override
  Widget build(BuildContext context) {
    final topic = state.selectedArchiveTopic;
    if (topic == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final files = state.displayArchiveFiles;
    final selected = files.any((file) => file.id == state.selectedArchiveFile?.id)
        ? state.selectedArchiveFile
        : null;
    final searching = state.archiveSearchQuery.trim().isNotEmpty;
    final s = state.strings;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      children: [
        Row(
          children: [
            if (!topic.isMain) ...[
              TopicEmoji(value: topic.icon, size: 16),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                s.archiveTopicHeadline(state.topicDisplayName(topic)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.noteTitleStyle.copyWith(
                  fontSize: 15,
                  height: 1.2,
                  color: AppColors.text.withValues(alpha: 0.94),
                ),
              ),
            ),
            _ArchiveSearchBar(
              open: _searchOpen,
              controller: _search,
              enabled: !state.archiveDeleteMode,
              hint: s['archiveSearchHint'],
              onChanged: state.onArchiveSearchQueryChanged,
              onToggle: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _search.clear();
                    state.onArchiveSearchQueryChanged('');
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!state.archiveDeleteMode) ...[
          if (selected == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                files.isEmpty
                    ? (searching
                        ? s['archiveNoSearchResults']
                        : s['archiveNoFiles'])
                    : s['archiveSelectFile'],
                style: AppTypography.metaStyle,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                height: 360,
                child: ArchiveFilePreview(
                  state: state,
                  file: selected,
                  onUnarchive: () => _unarchive(selected),
                  onDelete: () => _delete(selected),
                ),
              ),
            ),
        ],
        if (files.isEmpty && !state.archiveLoading)
          Text(
            searching ? s['archiveNoSearchResults'] : s['archiveNoFiles'],
            style: AppTypography.noteBodyStyle,
          )
        else
          ArchiveFileGrid(
            files: files,
            state: state,
            selectedFileId: selected?.id,
            onSelect: state.selectArchiveFile,
            deleteMode: state.archiveDeleteMode,
            markedForDelete: state.archiveDeleteSelection,
            onToggleDelete: state.toggleArchiveDeleteSelection,
            onContextMenu: state.archiveDeleteMode ? null : _fileMenu,
          ),
        if (state.archiveLoading)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: MainPaneLoader(compact: true),
          ),
      ],
    );
  }
}

class _ArchiveSearchBar extends StatelessWidget {
  const _ArchiveSearchBar({
    required this.open,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onChanged,
    required this.onToggle,
  });

  final bool open;
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: open ? 216 : 32,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.noteTop.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.noteBorder.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: hint,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: enabled ? onToggle : null,
              icon: AppIcon(
                open ? AppIcons.close : AppIcons.search,
                size: 16,
              ),
            ),
            if (open)
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  autofocus: true,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppTypography.metaStyle,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: AppTypography.noteBodyStyle.copyWith(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
