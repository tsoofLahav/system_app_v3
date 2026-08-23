import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/glass_surface.dart';
import '../topic/topic_appearance.dart';
import '../widgets/phone_tinted_name_tile.dart';
import './bring_file_catalog.dart';

Future<BrowseFileEntry?> showPhoneBringFileSheet({
  required BuildContext context,
  required AppState state,
}) {
  return showModalBottomSheet<BrowseFileEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PhoneBringFileSheet(state: state),
  );
}

class _PhoneBringFileSheet extends StatefulWidget {
  const _PhoneBringFileSheet({required this.state});

  final AppState state;

  @override
  State<_PhoneBringFileSheet> createState() => _PhoneBringFileSheetState();
}

class _PhoneBringFileSheetState extends State<_PhoneBringFileSheet> {
  final _search = TextEditingController();
  List<BrowseFileEntry> _all = const [];
  List<BrowseFileEntry> _filtered = const [];
  var _loading = true;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _search.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await _state.loadBringFileCatalog();
    if (!mounted) return;
    setState(() {
      _all = entries;
      _filtered = entries;
      _loading = false;
    });
  }

  void _applyFilter() {
    setState(() {
      _filtered = filterBringFileCatalog(
        _all,
        _search.text,
        topicLabel: _state.topicDisplayName,
        fileLabel: (file) => _state.fileDisplayName(file.name),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _state.strings;
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(s['bringFile'], style: AppTypography.noteTitleStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: DialogFieldStyle.decoration(
                    hintText: s['bringFileSearchHint'],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          s['bringFileEmpty'],
                          style: AppTypography.metaStyle,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final entry = _filtered[index];
                          return PhoneTintedNameTile(
                            title: _state.fileDisplayName(entry.file.name),
                            subtitle: s.bringFileFromTopicNamed(
                              _state.topicDisplayName(entry.topic),
                            ),
                            fileId: entry.file.id,
                            accent: TopicAppearance.accentFor(entry.topic),
                            isMainTopic: entry.topic.isMain,
                            onTap: () => Navigator.pop(context, entry),
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
