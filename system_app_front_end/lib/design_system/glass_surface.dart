import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Shared glass parameters — use presets instead of ad-hoc values.
class GlassStyleSpec {
  const GlassStyleSpec({
    required this.blurSigma,
    required this.tintOpacity,
    this.tintColor,
    this.showTopHighlight = true,
    this.elevation = 0,
    this.border,
    this.opaqueChrome = false,
  });

  final double blurSigma;
  final double tintOpacity;
  final Color? tintColor;
  final bool showTopHighlight;
  final double elevation;
  final BoxBorder? border;
  final bool opaqueChrome;
}

abstract final class AppGlassStyle {
  static const dialogTint = Color(0xFFDDF6F2);
  static const floatingRadius = 16.0;
  static const dialogRadius = 22.0;
  static const pillRadius = 999.0;

  static BoxBorder get _dialogBorder => Border.all(
        color: Colors.white.withValues(alpha: 0.68),
        width: 0.85,
      );

  static BoxBorder get _opaqueChromeBorder => Border.all(
        color: AppColors.noteBorder.withValues(alpha: 0.48),
        width: AppColors.filePaneBorderWidth,
      );

  static BoxBorder aiBorder([double alpha = 0.45]) => Border.all(
        color: AppColors.aiCyan.withValues(alpha: alpha),
        width: AppColors.filePaneBorderWidth,
      );

  static const dialog = GlassStyleSpec(
    blurSigma: 24,
    tintOpacity: 0.78,
    tintColor: dialogTint,
    showTopHighlight: true,
    elevation: 7,
    border: null,
  );

  static final floating = GlassStyleSpec(
    blurSigma: 24,
    tintOpacity: 0.78,
    tintColor: dialogTint,
    showTopHighlight: true,
    elevation: 4,
    border: _dialogBorder,
  );

  /// Bottom bar segments and `+` — solid white pills with lift shadow.
  static final opaqueChrome = GlassStyleSpec(
    blurSigma: 0,
    tintOpacity: 1,
    showTopHighlight: false,
    elevation: 0,
    border: _opaqueChromeBorder,
    opaqueChrome: true,
  );

  static final aiAccent = GlassStyleSpec(
    blurSigma: 0,
    tintOpacity: 1,
    showTopHighlight: false,
    elevation: 0,
    border: aiBorder(0.44),
    opaqueChrome: true,
  );
}

/// Frosted glass panel — blurs content behind it (liquid glass).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.style,
    this.borderRadius,
    this.blurSigma = 10,
    this.tintOpacity = 0.16,
    this.tintColor,
    this.showTopHighlight = true,
    this.border,
    this.padding,
    this.elevation = 0,
    this.opaqueChrome = false,
  });

  factory GlassSurface.styled({
    required GlassStyleSpec style,
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    BoxBorder? border,
    bool? showTopHighlight,
    double? elevation,
  }) {
    return GlassSurface(
      borderRadius: borderRadius,
      blurSigma: style.blurSigma,
      tintOpacity: style.tintOpacity,
      tintColor: style.tintColor,
      showTopHighlight: showTopHighlight ?? style.showTopHighlight,
      border: border ?? style.border,
      padding: padding,
      elevation: elevation ?? style.elevation,
      opaqueChrome: style.opaqueChrome,
      child: child,
    );
  }

  final Widget child;
  final GlassStyleSpec? style;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final double tintOpacity;
  final Color? tintColor;
  final bool showTopHighlight;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final double elevation;
  final bool opaqueChrome;

  static List<BoxShadow> get _opaqueChromeShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.11),
          blurRadius: 20,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final resolved = style;
    final radius = borderRadius ?? BorderRadius.zero;
    final effectiveBlur = resolved?.blurSigma ?? blurSigma;
    final effectiveTintOpacity = resolved?.tintOpacity ?? tintOpacity;
    final effectiveTintColor = resolved?.tintColor ?? tintColor;
    final effectiveHighlight = resolved?.showTopHighlight ?? showTopHighlight;
    final effectiveElevation = resolved?.elevation ?? elevation;
    final effectiveBorder = resolved?.border ?? border;
    final useOpaqueChrome = resolved?.opaqueChrome ?? opaqueChrome;

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (useOpaqueChrome) {
      return _OpaqueChromeShell(
        borderRadius: radius,
        border: effectiveBorder,
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: _frostedDecoration(
                  radius: radius,
                  tintColor: effectiveTintColor,
                  tintOpacity: effectiveTintOpacity,
                  border: effectiveBorder,
                  elevation: effectiveElevation,
                ),
              ),
            ),
            if (effectiveHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: const Alignment(0, 0.55),
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
              ),
            content,
          ],
        ),
      ),
    );
  }

  static BoxDecoration _frostedDecoration({
    required BorderRadius radius,
    required Color? tintColor,
    required double tintOpacity,
    required BoxBorder? border,
    required double elevation,
  }) {
    Color blendTint(double alpha) {
      final base = Colors.white.withValues(alpha: alpha);
      if (tintColor == null) return base;
      return Color.alphaBlend(
        tintColor.withValues(alpha: alpha * 0.42),
        base,
      );
    }

    return BoxDecoration(
      borderRadius: radius,
      border: border ??
          Border.all(
            color: Colors.white.withValues(alpha: 0.62),
            width: 0.85,
          ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          blendTint(tintOpacity + 0.06),
          blendTint(tintOpacity - 0.02),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: (tintColor ?? AppColors.noteShadow).withValues(
            alpha: tintColor != null ? 0.1 : 0.05,
          ),
          blurRadius: 20 + elevation,
          offset: Offset(0, 5 + elevation * 0.5),
        ),
      ],
    );
  }
}

/// Solid white floating chrome — no backdrop blur (avoids muddy translucency).
class _OpaqueChromeShell extends StatelessWidget {
  const _OpaqueChromeShell({
    required this.borderRadius,
    required this.child,
    this.border,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = border ?? AppGlassStyle._opaqueChromeBorder;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: Colors.white,
        border: effectiveBorder,
        boxShadow: GlassSurface._opaqueChromeShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}

/// Ambient shadow band at the bottom of the workspace behind floating chrome.
class ChromeFloorShadow extends StatelessWidget {
  const ChromeFloorShadow({super.key, this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.035),
                Colors.black.withValues(alpha: 0.085),
              ],
              stops: const [0.0, 0.42, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Capsule segment for the bottom bar and similar floating tool groups.
class GlassBarSegment extends StatelessWidget {
  const GlassBarSegment({
    super.key,
    required this.child,
    this.style,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    this.label,
    this.labelOnBorder = false,
  });

  final Widget child;
  final GlassStyleSpec? style;
  final double? height;
  final EdgeInsetsGeometry padding;
  final String? label;

  /// When true, [label] sits on the top outline (for the AI segment).
  final bool labelOnBorder;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? AppGlassStyle.opaqueChrome;
    final segment = GlassSurface.styled(
      style: resolvedStyle,
      borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
      padding: padding,
      child: height != null
          ? SizedBox(height: height, child: child)
          : child,
    );

    if (label == null) return segment;

    if (labelOnBorder) {
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          segment,
          Transform.translate(
            offset: const Offset(0, -5),
            child: _OutlineSegmentLabel(text: label!),
          ),
        ],
      );
    }

    return segment;
  }
}

class _OutlineSegmentLabel extends StatelessWidget {
  const _OutlineSegmentLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.metaStyle.copyWith(
        fontSize: 9,
        letterSpacing: 0.6,
        color: AppColors.aiCyan.withValues(alpha: 0.85),
        fontWeight: FontWeight.w500,
        height: 1,
      ),
    );
  }
}

/// Floating glass capsule with horizontal inset from the window edges.
class FloatingGlassPill extends StatelessWidget {
  const FloatingGlassPill({
    super.key,
    required this.child,
    this.horizontalMargin = 20,
    this.verticalMargin = 0,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.expandWidth = false,
  });

  final Widget child;
  final double horizontalMargin;
  final double verticalMargin;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface.styled(
      style: AppGlassStyle.floating,
      borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
      padding: padding,
      child: height != null
          ? SizedBox(
              width: expandWidth ? double.infinity : null,
              height: height,
              child: child,
            )
          : child,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      child: expandWidth ? surface : Center(child: surface),
    );
  }
}

/// Small circular glass control — always neutral (no topic tint).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 34,
    this.iconSize = 16,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _OpaqueChromeShell(
        borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: AppColors.text.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassDialog extends StatelessWidget {
  const AppGlassDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 420,
  });

  final Widget title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final separator = AppColors.text.withValues(alpha: 0.11);
    final actionText = AppTypography.metaStyle.copyWith(
      color: AppColors.text.withValues(alpha: 0.88),
      fontSize: 12,
    );

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: GlassSurface.styled(
          style: AppGlassStyle.dialog,
          borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
          border: AppGlassStyle._dialogBorder,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: DefaultTextStyle(
                  textAlign: TextAlign.center,
                  style: AppTypography.noteTitleStyle.copyWith(
                    fontSize: 15,
                    color: AppColors.text.withValues(alpha: 0.94),
                  ),
                  child: title,
                ),
              ),
              const SizedBox(height: 12),
              _GlassDivider(color: separator),
              const SizedBox(height: 12),
              DefaultTextStyle(
                style: AppTypography.noteBodyStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.text.withValues(alpha: 0.9),
                ),
                child: child,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _GlassDivider(color: separator),
                const SizedBox(height: 10),
                DefaultTextStyle(
                  style: actionText,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  const _GlassDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
