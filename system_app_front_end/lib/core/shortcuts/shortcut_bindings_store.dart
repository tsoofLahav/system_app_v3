import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'shortcut_binding.dart';
import 'shortcut_catalog.dart';

const _storageKey = 'shortcut_bindings';

class ShortcutBindingsStore {
  ShortcutBindingsStore({Map<String, ShortcutBinding>? overrides})
      : _overrides = Map<String, ShortcutBinding>.from(overrides ?? {});

  Map<String, ShortcutBinding> _overrides;

  static Future<ShortcutBindingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return ShortcutBindingsStore();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return ShortcutBindingsStore();
      final overrides = <String, ShortcutBinding>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        overrides[entry.key.toString()] = ShortcutBinding.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      return ShortcutBindingsStore(overrides: overrides);
    } catch (_) {
      return ShortcutBindingsStore();
    }
  }

  ShortcutBinding bindingFor(String actionId) {
    final override = _overrides[actionId];
    if (override != null && override.isValid) return override;
    final action = shortcutActionById(actionId);
    return action?.defaultBinding ?? const ShortcutBinding(keyId: 0);
  }

  Map<String, ShortcutBinding> resolvedBindings() {
    return {
      for (final action in kShortcutCatalog)
        action.id: bindingFor(action.id),
    };
  }

  String? bindingOwner(String actionId, ShortcutBinding binding) {
    if (!binding.isValid) return null;
    for (final action in kShortcutCatalog) {
      if (action.id == actionId) continue;
      final other = bindingFor(action.id);
      if (other == binding) return action.id;
    }
    return null;
  }

  Future<void> setBinding(String actionId, ShortcutBinding binding) async {
    if (!binding.isValid) return;
    _overrides[actionId] = binding;
    await _persist();
  }

  Future<void> resetBinding(String actionId) async {
    _overrides.remove(actionId);
    await _persist();
  }

  Future<void> resetAll() async {
    _overrides.clear();
    await _persist();
  }

  bool hasOverride(String actionId) => _overrides.containsKey(actionId);

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      for (final entry in _overrides.entries)
        entry.key: entry.value.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(payload));
  }
}
