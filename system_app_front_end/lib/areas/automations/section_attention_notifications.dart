import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import './section_attention_notices.dart';

/// iOS local notifications for open section-window attention.
///
/// Each notice is its own notification. The app-icon badge is the count.
/// No-op on anything that is not native iOS.
class SectionAttentionNotifications {
  SectionAttentionNotifications._();

  static final instance = SectionAttentionNotifications._();

  static const _clearBadgeId = 0;
  static const _thread = 'section_windows';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _shownIds = <int>{};
  var _ready = false;

  Future<void> sync({
    required List<SectionAttentionNotice> notices,
    required String body,
  }) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _ensureReady();
      if (!_ready) return;
      final nextIds = {for (final notice in notices) notice.id};
      for (final id in _shownIds.difference(nextIds)) {
        await _plugin.cancel(id);
      }
      if (notices.isEmpty) {
        await _setBadge(0);
        _shownIds.clear();
        return;
      }
      final inForeground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      for (final notice in notices) {
        final isNew = !_shownIds.contains(notice.id);
        await _plugin.show(
          notice.id,
          notice.title,
          body,
          NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentSound: false,
              presentBadge: true,
              presentBanner: isNew && !inForeground,
              presentList: true,
              badgeNumber: notices.length,
              threadIdentifier: _thread,
            ),
          ),
        );
      }
      _shownIds
        ..clear()
        ..addAll(nextIds);
    } catch (_) {
      // Permission denied or plugin missing — in-app dots still work.
    }
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: false,
          defaultPresentAlert: false,
          defaultPresentSound: false,
          defaultPresentBadge: true,
          defaultPresentBanner: false,
          defaultPresentList: true,
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: false);
    _ready = true;
  }

  Future<void> _setBadge(int count) async {
    await _plugin.show(
      _clearBadgeId,
      null,
      null,
      NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentSound: false,
          presentBadge: true,
          presentBanner: false,
          presentList: false,
          badgeNumber: count,
        ),
      ),
    );
    if (count == 0) await _plugin.cancel(_clearBadgeId);
  }
}

final sectionAttentionNotifications = SectionAttentionNotifications.instance;
