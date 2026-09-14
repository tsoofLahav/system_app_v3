import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/section_attention_notifications.dart';
import 'package:system_app_front_end/areas/automations/section_attention_notices.dart';
import 'package:system_app_front_end/areas/automations/push_registration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'APNs enrollment reconciles badge without posting local duplicates',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      const local = MethodChannel('dexterous.com/flutter/local_notifications');
      final calls = <MethodCall>[];
      final native = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(local, (call) async {
        calls.add(call);
        return call.method == 'initialize' ||
                call.method == 'requestPermissions'
            ? true
            : null;
      });
      messenger.setMockMethodCallHandler(PushRegistration.channel, (
        call,
      ) async {
        native.add(call);
        return null;
      });
      try {
        final service = SectionAttentionNotifications.forTesting();
        await service.sync(
          notices: [const SectionAttentionNotice(id: 1, title: 'Evening')],
          body: 'Tasks',
          remoteEnabled: true,
        );
        await service.sync(notices: [], body: 'Tasks', remoteEnabled: true);
        expect(calls.where((call) => call.method == 'show'), isEmpty);
        expect(native.map((call) => call.arguments['badge']), [1, 0]);
      } finally {
        messenger.setMockMethodCallHandler(local, null);
        messenger.setMockMethodCallHandler(PushRegistration.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
