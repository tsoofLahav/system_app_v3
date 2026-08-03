import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/color_dialog.dart';
import '../topic/topic_appearance.dart';

/// Topic theme colour — full spectrum via [showAppColorDialog], with the
/// familiar presets as shortcuts so wayfinding colours stay one tap away.
Future<String?> showTopicColorDialog({
  required BuildContext context,
  required AppStrings strings,
  required String selectedHex,
}) {
  return showAppColorDialog(
    context: context,
    strings: strings,
    selectedHex: selectedHex,
    presetHexes: TopicAppearance.presetColors,
  );
}
