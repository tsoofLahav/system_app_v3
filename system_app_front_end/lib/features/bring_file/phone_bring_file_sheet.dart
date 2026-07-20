import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/browse/bring_file_catalog.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<BrowseFileEntry?> showPhoneBringFileSheet(
  BuildContext context,
  AppState state,
) {
  return showModalBottomSheet<BrowseFileEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PhoneBringFileSheet(state: state),
  );
}

class PhoneBringFileSheet extends StatefulWidget {
  const PhoneBringFileSheet({super.key, required this.state});

  final AppState state;

  @override
  State<PhoneBringFileSheet> createState() => _PhoneBringFileSheetState();
}

class _PhoneBringFileSheetState extends State<PhoneBringFileSheet> {
  final _searchController = TextEditingController();
  List<BrowseFileEntry> _catalog = const [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.state.loadBringFileCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<BrowseFileEntry> get _filtered {
    return filterBringFileCatalog(_catalog, _searchController.text);
  }

  void _select(BrowseFileEntry entry) {
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Material(
            color: Colors.transparent,
            child: GlassSurface(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              tintOpacity: 0.94,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s['bringFile'],
                            style: AppTypography.noteTitleStyle,
                          ),
                        ),
                        IconButton(
                          icon: const AppIcon(AppIcons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: s['bringFileSearchHint'],
                        prefixIcon: const AppIcon(AppIcons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(child: Text(_error!))
                        : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                s['bringFileEmpty'],
                                style: AppTypography.noteBodyStyle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) => Divider(
                              height: 1,
                              color: AppColors.noteBorder.withValues(alpha: 0.4),
                            ),
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              return ListTile(
                                title: Text(
                                  entry.fileLabel,
                                  style: AppTypography.noteBodyStyle,
                                ),
                                subtitle: Text(
                                  s.bringFileFromTopicNamed(entry.topicLabel),
                                  style: AppTypography.metaStyle,
                                ),
                                onTap: () => _select(entry),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
