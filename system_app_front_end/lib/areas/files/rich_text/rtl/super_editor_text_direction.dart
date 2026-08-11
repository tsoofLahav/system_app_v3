/// Super Editor paragraph direction — part of the [RTL solution](RTL.md).
///
/// Stock SE builders use [getParagraphDirection], which treats empty text as
/// LTR. That makes the caret sit on the left until the first Hebrew character,
/// then jump right. We resolve direction the same way as [FormattedTextField]:
/// first strong character, else ambient UI [Directionality].
library;

import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import './paragraph_text_direction.dart';

/// Patches [TextComponentViewModel.textDirection] after a stock SE builder runs.
class AmbientTextDirectionBuilder implements ComponentBuilder {
  const AmbientTextDirectionBuilder({
    required this.ambient,
    required this.inner,
  });

  final TextDirection ambient;
  final ComponentBuilder inner;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    final vm = inner.createViewModel(document, node);
    if (vm == null) return null;
    if (vm is TextComponentViewModel && node is TextNode) {
      vm.textDirection =
          detectParagraphTextDirection(node.text.toPlainText()) ?? ambient;
    }
    return vm;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    return inner.createComponent(componentContext, componentViewModel);
  }
}

/// Paragraph / list / blockquote builders with ambient-aware empty direction.
List<ComponentBuilder> ambientAwareTextBuilders(TextDirection ambient) {
  return [
    AmbientTextDirectionBuilder(
      ambient: ambient,
      inner: const BlockquoteComponentBuilder(),
    ),
    AmbientTextDirectionBuilder(
      ambient: ambient,
      inner: const ParagraphComponentBuilder(),
    ),
    AmbientTextDirectionBuilder(
      ambient: ambient,
      inner: const ListItemComponentBuilder(),
    ),
  ];
}
