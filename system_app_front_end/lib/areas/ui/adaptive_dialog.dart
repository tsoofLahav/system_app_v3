import 'package:flutter/material.dart';

import '../../core/platform/app_form_factor.dart';
import './app_typography.dart';
import './dialog_metrics.dart';
import './glass_surface.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useBottomSheet = true,
  bool isDismissible = true,
}) {
  // Phone uses showDialog — Scaffold already has a persistent bottom tools strip,
  // and nested modal bottom sheets are unreliable on iOS.
  if (isPhoneLayout) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: builder,
  );
}

/// Phone-friendly shell around [AppGlassDialog] content.
class AppAdaptiveDialogShell extends StatelessWidget {
  const AppAdaptiveDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = AppDialogMetrics.maxWidth,
    this.headerAccent,
    this.headerAccentIsMain = false,
    this.headerAccentTintAlpha,
  });

  final Widget title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final Color? headerAccent;
  final bool headerAccentIsMain;
  final double? headerAccentTintAlpha;

  @override
  Widget build(BuildContext context) {
    if (isPhoneLayout) {
      return Dialog(
        insetPadding: AppDialogMetrics.phoneInset,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            maxWidth: double.infinity,
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(16),
            tintOpacity: 0.94,
            headerAccent: headerAccent,
            headerAccentIsMain: headerAccentIsMain,
            headerAccentTintAlpha: headerAccentTintAlpha,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: AppDialogMetrics.phoneTitlePadding,
                  child: DefaultTextStyle(
                    style: AppTypography.noteTitleStyle,
                    child: title,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: AppDialogMetrics.phoneBodyPadding,
                    child: child,
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: AppDialogMetrics.phoneActionsPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AppGlassDialog(
      title: title,
      actions: actions,
      width: width,
      headerAccent: headerAccent,
      headerAccentIsMain: headerAccentIsMain,
      headerAccentTintAlpha: headerAccentTintAlpha,
      child: child,
    );
  }
}
