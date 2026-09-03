import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../../files/editor/document_pane.dart';
import '../../ui/app_typography.dart';
import '../shell/app_bottom_bar.dart';
import '../shell/phone_visible_file.dart';
import './topic_appearance.dart';

/// One file at a time. Swipe toward the end of the row — right in English,
/// left in Hebrew. [PageView.reverse] is not set: Directionality already
/// mirrors the axis.
class PhoneTopicView extends StatefulWidget {
  const PhoneTopicView({
    super.key,
    required this.state,
    required this.topic,
    required this.files,
  });

  final AppState state;
  final Topic topic;
  final List<AppFile> files;

  @override
  State<PhoneTopicView> createState() => _PhoneTopicViewState();
}

class _PhoneTopicViewState extends State<PhoneTopicView> {
  late final PageController _pageController;
  var _currentPage = 0;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishVisibleName());
  }

  @override
  void didUpdateWidget(covariant PhoneTopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic.id != widget.topic.id) {
      _currentPage = 0;
      _jumpWhenReady(0);
      _publishVisibleName();
      return;
    }
    if (widget.files.isEmpty) {
      _currentPage = 0;
      _publishVisibleName();
      return;
    }
    final oldIds = {for (final file in oldWidget.files) file.id};
    final newFirst = widget.files.first;
    if (!oldIds.contains(newFirst.id)) {
      _currentPage = 0;
      _jumpWhenReady(0);
      _publishVisibleName();
      return;
    }
    final oldFiles = oldWidget.files;
    final currentId = (_currentPage >= 0 && _currentPage < oldFiles.length)
        ? oldFiles[_currentPage].id
        : null;
    final index = currentId == null
        ? -1
        : widget.files.indexWhere((file) => file.id == currentId);
    if (index >= 0) {
      if (index != _currentPage) {
        _currentPage = index;
        _jumpWhenReady(index);
      }
      _publishVisibleName();
      return;
    }
    _currentPage = 0;
    _jumpWhenReady(0);
    _publishVisibleName();
  }

  @override
  void dispose() {
    PhoneVisibleFile.setName(null);
    _pageController.dispose();
    super.dispose();
  }

  void _publishVisibleName() {
    if (!mounted || widget.files.isEmpty) {
      PhoneVisibleFile.setName(null);
      return;
    }
    final page = _currentPage.clamp(0, widget.files.length - 1);
    PhoneVisibleFile.setName(
      state.fileDisplayName(widget.files[page].name),
    );
  }

  void _jumpWhenReady(int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            state.strings['topicNoFiles'],
            textAlign: TextAlign.center,
            style: AppTypography.metaStyle,
          ),
        ),
      );
    }

    final page = _currentPage.clamp(0, files.length - 1);

    return PageView.builder(
      controller: _pageController,
      itemCount: files.length,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
        _publishVisibleName();
      },
      itemBuilder: (context, index) {
        if ((index - page).abs() > 1) {
          return const SizedBox.expand();
        }
        return _page(files[index], isCurrent: index == page);
      },
    );
  }

  Widget _page(AppFile file, {required bool isCurrent}) {
    final paneTopic = state.canvasTopicFor(widget.topic, file);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppBottomBarMetrics.phonePeekInset,
        AppBottomBarMetrics.phoneVerticalPeek,
        AppBottomBarMetrics.phonePeekInset,
        AppBottomBarMetrics.phoneVerticalPeek,
      ),
      child: DocumentPane(
        key: ValueKey(file.id),
        topic: paneTopic,
        file: file,
        state: state,
        accent: TopicAppearance.accentFor(paneTopic),
        isBrought: state.isBroughtFileOnCanvas(widget.topic, file.id),
        autoOpenPendingReview: isCurrent,
        onDelete: () => state.deleteFile(file),
      ),
    );
  }
}
