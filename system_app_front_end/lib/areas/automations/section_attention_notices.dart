import './automation.dart';

/// One iOS notification for one section that currently has attention.
class SectionAttentionNotice {
  const SectionAttentionNotice({required this.id, required this.title});

  final int id;
  final String title;
}

/// Sections whose in-app red dot is on — each becomes its own notification.
/// The badge count is [notices].length.
List<SectionAttentionNotice> sectionAttentionNotices({
  required List<Automation> automations,
  required String Function(Automation) titleOf,
  required bool Function(Automation) stillHasWork,
}) {
  return [
    for (final automation in automations)
      if (automation.isSectionWindow &&
          automation.attention &&
          stillHasWork(automation))
        SectionAttentionNotice(
          id: automation.id,
          title: titleOf(automation),
        ),
  ];
}
