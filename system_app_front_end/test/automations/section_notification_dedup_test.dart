import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/section_attention_notices.dart';
import 'package:system_app_front_end/areas/automations/section_attention_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unchanged and overlapping refreshes do not repost open sections',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'initialize' ||
                call.method == 'requestPermissions')
              return true;
            return null;
          });
      try {
        final notifications = SectionAttentionNotifications.forTesting();
        const first = SectionAttentionNotice(id: 1, title: 'Morning');
        const second = SectionAttentionNotice(id: 2, title: 'Evening');
        await Future.wait(
          List.generate(
            3,
            (_) => notifications.sync(notices: [first], body: 'Open tasks'),
          ),
        );
        expect(
          calls.where((c) => c.method == 'show' && c.arguments['id'] == 1),
          hasLength(1),
        );
        final count = calls.length;
        await notifications.sync(notices: [first], body: 'Open tasks');
        expect(calls.length, count);
        await notifications.sync(notices: [first, second], body: 'Open tasks');
        expect(
          calls.where((c) => c.method == 'show' && c.arguments['id'] == 1),
          hasLength(1),
        );
        expect(
          calls.where((c) => c.method == 'show' && c.arguments['id'] == 2),
          hasLength(1),
        );
        await notifications.sync(notices: [second], body: 'Open tasks');
        expect(
          calls.where((c) => c.method == 'cancel' && c.arguments == 1),
          hasLength(1),
        );
        await notifications.sync(notices: [], body: 'Open tasks');
        final emptyCount = calls.length;
        await notifications.sync(notices: [], body: 'Open tasks');
        expect(calls.length, emptyCount);
        await notifications.sync(notices: [first], body: 'Open tasks');
        expect(
          calls.where((c) => c.method == 'show' && c.arguments['id'] == 1),
          hasLength(2),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
