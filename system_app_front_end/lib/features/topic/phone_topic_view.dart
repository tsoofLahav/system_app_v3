import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';
import '../../shared/widgets/file_section.dart';

sealed class PhoneFilePage {}

class PhoneFilePageFile extends PhoneFilePage {
  PhoneFilePageFile(this.file);

  final AppFile file;
}

class PhoneFilePageSeparator extends PhoneFilePage {}

class PhoneTopicView extends StatefulWidget {
  const PhoneTopicView({
    super.key,
    required this.state,
    required this.topic,
    required this.mainFiles,
    required this.secondaryFiles,
    required this.accent,
    required this.stale,
  });

  final AppState state;
  final Topic topic;
  final List<AppFile> mainFiles;
  final List<AppFile> secondaryFiles;
  final Color accent;
  final bool stale;

  @override
  State<PhoneTopicView> createState() => _PhoneTopicViewState();
}

class _PhoneTopicViewState extends State<PhoneTopicView> {
  late PageController _pageController;
  var _currentPage = 0;

  AppState get state => widget.state;
  Topic get topic => widget.topic;

  List<PhoneFilePage> get _phonePages {
    final pages = <PhoneFilePage>[];
    final mains = widget.mainFiles;
    final secondaries = widget.secondaryFiles;

    if (mains.isNotEmpty) {
      for (final file in mains) {
        pages.add(PhoneFilePageFile(file));
      }
      if (secondaries.isNotEmpty) {
        pages.add(PhoneFilePageSeparator());
        for (final file in secondaries) {
          pages.add(PhoneFilePageFile(file));
        }
      }
    } else {
      for (final file in secondaries) {
        pages.add(PhoneFilePageFile(file));
      }
    }
    return pages;
  }

  int get _filePageCount =>
      _phonePages.whereType<PhoneFilePageFile>().length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _applyPhoneFocus();
  }

  @override
  void didUpdateWidget(covariant PhoneTopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pages = _phonePages;
    if (_currentPage >= pages.length) {
      _currentPage = pages.isEmpty ? 0 : pages.length - 1;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
    }
    if (state.phoneFocusFileId != null) {
      _applyPhoneFocus();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyPhoneFocus() {
    final fileId = state.phoneFocusFileId;
    if (fileId == null) return;

    final pages = _phonePages;
    final index = pages.indexWhere(
      (page) => page is PhoneFilePageFile && page.file.id == fileId,
    );
    if (index < 0) {
      state.clearPhoneFocusFile();
      return;
    }

    _currentPage = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_currentPage);
      state.clearPhoneFocusFile();
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
  }

  String _pageIndicatorLabel(List<PhoneFilePage> pages) {
    final current = pages[_currentPage];
    if (current is PhoneFilePageSeparator) return '—';
    final filePages = pages.whereType<PhoneFilePageFile>().toList();
    final fileIndex = filePages.indexWhere(
      (page) => page.file.id == (current as PhoneFilePageFile).file.id,
    );
    if (fileIndex < 0) return '';
    return '${fileIndex + 1} / ${filePages.length}';
  }

  Widget _buildSeparatorPage(String label) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Divider(
              color: AppColors.noteBorder.withValues(alpha: 0.55),
              thickness: 1,
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: AppTypography.noteTitleStyle.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Divider(
              color: AppColors.noteBorder.withValues(alpha: 0.55),
              thickness: 1,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _phonePages;
    final detail = state.selectedDetail;
    final s = state.strings;

    if (widget.stale || detail == null) {
      return Center(
        child: CircularProgressIndicator(
          color: widget.accent.withValues(alpha: 0.7),
        ),
      );
    }

    if (_filePageCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            s['noFilesYet'],
            style: AppTypography.noteBodyStyle,
          ),
        ),
      );
    }

    return TopicCanvasBackground(
      accent: widget.accent,
      isMain: topic.isMain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              reverse: state.isRtl,
              itemCount: pages.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final page = pages[index];
                return switch (page) {
                  PhoneFilePageSeparator() => _buildSeparatorPage(
                    s.moreFiles(widget.secondaryFiles.length),
                  ),
                  PhoneFilePageFile(:final file) => Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: FileSection(
                      key: ValueKey(file.id),
                      topic: topic,
                      file: file,
                      blocks: detail.blocksByFileId[file.id] ?? [],
                      state: state,
                      accent: widget.accent,
                      onDelete: () => state.deleteFile(topic, file),
                    ),
                  ),
                };
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _pageIndicatorLabel(pages),
              textAlign: TextAlign.center,
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
