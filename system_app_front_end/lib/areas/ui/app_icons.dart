import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import './app_colors.dart';

/// Lucide stroke icons (weight 200) — simple, modern, consistent across the app.
/// Phone floating chrome paints the same glyphs at [AppIcon.phoneBarWeight].
abstract final class AppIcons {
  // Bottom bar & AI tools
  static const preferences = LucideIcons.settings2200;
  static const automations = LucideIcons.clock200;
  static const runNow = LucideIcons.play200;
  static const edit = LucideIcons.pencil200;
  static const layout = LucideIcons.layoutGrid200;
  static const ai = LucideIcons.sparkles200;
  static const consult = LucideIcons.messageCircle200;
  static const summarize = LucideIcons.filePlus200;
  static const smartList = LucideIcons.listPlus200;
  static const image = LucideIcons.image200;
  static const graph = LucideIcons.chartColumn200;
  static const diagramGraphConfig = LucideIcons.network200;
  static const review = LucideIcons.scanSearch200;
  static const pinToBar = LucideIcons.pin200;
  static const unpinFromBar = LucideIcons.pinOff200;
  static const moveFileAi = LucideIcons.folderOutput200;
  static const crop = LucideIcons.crop200;

  // General UI
  static const menu = LucideIcons.menu200;
  static const add = LucideIcons.plus200;
  static const more = LucideIcons.ellipsis200;
  static const check = LucideIcons.check200;
  static const circle = LucideIcons.circle200;
  static const chevronRight = LucideIcons.chevronRight200;
  static const chevronLeft = LucideIcons.chevronLeft200;
  static const chevronDown = LucideIcons.chevronDown200;
  static const chevronUp = LucideIcons.chevronUp200;
  static const arrowUp = LucideIcons.arrowUp200;
  static const arrowDown = LucideIcons.arrowDown200;
  static const arrowLeft = LucideIcons.arrowLeft200;
  static const arrowRight = LucideIcons.arrowRight200;
  static const addFile = LucideIcons.filePlus200;
  static const unmarkTasks = LucideIcons.listChecks200;
  static const archiveFiles = LucideIcons.archive200;
  static const fillFile = LucideIcons.filePen200;
  static const bringFile = LucideIcons.folderInput200;
  static const logForProject = LucideIcons.notebookPen200;
  static const drag = LucideIcons.gripVertical200;
  static const paneDrag = LucideIcons.gripHorizontal200;
  static const arrange = LucideIcons.layoutPanelTop200;
  static const swap = LucideIcons.arrowLeftRight200;
  static const close = LucideIcons.x200;
  static const enterObject = LucideIcons.squareArrowDown200;
  static const leaveObject = LucideIcons.squareArrowUp200;
  static const trash = LucideIcons.trash2200;
  static const search = LucideIcons.search200;
  static const colorWheel = LucideIcons.palette200;
  static const calendar = LucideIcons.calendar200;
  static const pending = LucideIcons.clock200;

  // Emoji picker categories
  static const recent = LucideIcons.clock200;
  static const smiley = LucideIcons.smile200;
  static const animal = LucideIcons.rabbit200;
  static const food = LucideIcons.coffee200;
  static const activity = LucideIcons.dumbbell200;
  static const travel = LucideIcons.car200;
  static const object = LucideIcons.lightbulb200;
  static const symbol = LucideIcons.hash200;
  static const flag = LucideIcons.flag200;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.enabled = true,
    this.textDirection,
    this.weight,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final bool enabled;

  /// Chrome arrows pass [TextDirection.ltr] so left stays left in Hebrew.
  final TextDirection? textDirection;

  /// Lucide stroke for phone floating chrome — thicker than desktop 200,
  /// lighter than 400 so the glass pills stay readable without shouting.
  static const phoneBarWeight = 300;

  /// Lucide stroke. Phone bars use [phoneBarWeight] so the icons do not
  /// vanish on glass. Desktop chrome stays at the catalog 200.
  final int? weight;

  IconData get _painted {
    final w = weight;
    if (w == null || w == 200) return icon;
    return IconData(
      icon.codePoint,
      fontFamily: 'Lucide$w',
      fontPackage: icon.fontPackage ?? 'lucide_icons_flutter',
      matchTextDirection: icon.matchTextDirection,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Icon(
      _painted,
      size: size,
      color:
          color ??
          (enabled
              ? AppColors.text.withValues(alpha: 0.82)
              : AppColors.textHint.withValues(alpha: 0.38)),
      textDirection: textDirection,
    );
  }
}
