import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/topic/topic_appearance.dart';

void main() {
  test('typed topic is type - name and emoji', () {
    expect(
      TopicAppearance.broughtOriginLabel(
        topicName: 'Onboarding',
        icon: '🚀',
        typeDisplay: 'Process',
      ),
      'Process - Onboarding🚀',
    );
  });

  test('untyped topic is name and emoji, with no empty type prefix', () {
    expect(
      TopicAppearance.broughtOriginLabel(
        topicName: 'Notes',
        icon: '📌',
      ),
      'Notes📌',
    );
  });

  test('empty icon does not inject the default pin', () {
    expect(
      TopicAppearance.broughtOriginLabel(topicName: 'Work', icon: ''),
      'Work',
    );
  });
}
