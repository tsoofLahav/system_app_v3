import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/api_service.dart';

/// Native iOS owns APNs registration; AppState supplies the active workspace.
class PushRegistration {
  static const channel = MethodChannel('system_app/push');
  static Future<void> _registrationTail = Future<void>.value();
  static const _enabledKey = 'apns_enrolled';
  final ApiService api;
  PushRegistration(this.api);
  bool enabled = false;
  bool ready = kIsWeb || !Platform.isIOS;
  bool _busy = false;
  bool _disposed = false;

  Future<void> register(String language) async {
    if (kIsWeb || !Platform.isIOS || _busy || _disposed) return;
    _busy = true;
    // Serialize across AppState instances: an old profile's slow registration
    // must finish before the new profile replaces it on the server.
    final next = _registrationTail.then((_) async {
      if (_disposed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        enabled = prefs.getBool(_enabledKey) ?? false;
        final native = await channel.invokeMapMethod<String, dynamic>(
          'register',
        );
        if (_disposed || native == null || native['token'] == null) return;
        final response = await api.post('/push-devices/register', {
          ...native,
          'language': language,
        });
        enabled = response['enabled'] == true;
        await prefs.setBool(_enabledKey, enabled);
      } catch (_) {
        // Keep previous enrollment during an outage to avoid duplicate locals.
      } finally {
        ready = true;
      }
    });
    _registrationTail = next;
    try {
      await next;
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
  }
}
