/// Known values for [ViewSection.sectionFlag] / [Task.sectionFlag].
abstract final class ViewSectionFlags {
  static const important = 'important';
}

bool sectionFlagIsImportant(String? flag) => flag == ViewSectionFlags.important;
