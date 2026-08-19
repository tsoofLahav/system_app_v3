import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../files/data/app_file.dart';
import '../layout/topic_file_slots.dart';

/// Local persist for files visiting Home, plus the mixed Home canvas order.
///
/// Visiting files stay on their own topics. The canvas order is this device's
/// arrangement of visits among Home's files; it is not `order_index`.
class BroughtFileLayout {
  const BroughtFileLayout({
    this.visitIds = const [],
    this.order = const [],
  });

  /// Files currently visiting Home, in canvas order.
  final List<int> visitIds;

  /// Full Home canvas order (visits and Home files interleaved). Empty means
  /// the default: visits first, then Home files by `order_index`.
  final List<int> order;

  bool get isEmpty => visitIds.isEmpty;
}

/// Places visiting files among Home's own files using a stored canvas order.
List<AppFile> mergeHomeCanvasFiles({
  required List<AppFile> homeFiles,
  required List<AppFile> visits,
  List<int> storedOrder = const [],
}) {
  final homeOrdered = orderedFiles(homeFiles);
  if (visits.isEmpty) return homeOrdered;
  if (storedOrder.isEmpty) return [...visits, ...homeOrdered];

  final byId = <int, AppFile>{
    for (final file in homeOrdered) file.id: file,
    for (final file in visits) file.id: file,
  };
  final seen = <int>{};
  final placed = <AppFile>[];
  for (final id in storedOrder) {
    final file = byId[id];
    if (file == null || !seen.add(id)) continue;
    placed.add(file);
  }
  final missingVisits = [
    for (final file in visits)
      if (!seen.contains(file.id)) file,
  ];
  final missingHome = [
    for (final file in homeOrdered)
      if (!seen.contains(file.id)) file,
  ];
  return [...missingVisits, ...missingHome, ...placed];
}

/// Local persist for files visiting Home. They stay on their own topics.
class BroughtFileStore {
  static const prefix = 'brought_file_ids';
  static const legacyPrefix = 'brought_file_id';

  static String keyFor(int workspaceId) => '${prefix}_$workspaceId';

  static String legacyKeyFor(int workspaceId) => '${legacyPrefix}_$workspaceId';

  Future<BroughtFileLayout> load(int workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFor(workspaceId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final fromList = _idsFromJson(decoded);
        if (fromList != null) {
          return BroughtFileLayout(visitIds: fromList);
        }
        if (decoded is Map) {
          return BroughtFileLayout(
            visitIds: _idsFromJson(decoded['visitIds']) ?? const [],
            order: _idsFromJson(decoded['order']) ?? const [],
          );
        }
      } catch (_) {}
    }
    final legacy = prefs.getInt(legacyKeyFor(workspaceId));
    if (legacy == null) return const BroughtFileLayout();
    return BroughtFileLayout(visitIds: [legacy]);
  }

  Future<void> save(int workspaceId, BroughtFileLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    final key = keyFor(workspaceId);
    await prefs.remove(legacyKeyFor(workspaceId));
    if (layout.visitIds.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'visitIds': layout.visitIds,
        'order': layout.order,
      }),
    );
  }

  static List<int>? _idsFromJson(Object? decoded) {
    if (decoded is! List) return null;
    return [
      for (final value in decoded)
        if (value is int)
          value
        else if (value is num)
          value.toInt(),
    ];
  }
}
