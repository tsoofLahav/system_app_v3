import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_colors.dart';

/// Lucide stroke icons (weight 200) — simple, modern, consistent across the app.
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
  static const review = LucideIcons.scanSearch200;
  static const crop = LucideIcons.crop200;

  // General UI
  static const add = LucideIcons.plus200;
  static const more = LucideIcons.ellipsis200;
  static const check = LucideIcons.check200;
  static const circle = LucideIcons.circle200;
  static const chevronRight = LucideIcons.chevronRight200;
  static const chevronLeft = LucideIcons.chevronLeft200;
  static const chevronDown = LucideIcons.chevronDown200;
  static const addFile = LucideIcons.filePlus200;
  static const bringFile = LucideIcons.folderInput200;
  static const moveFileToTopic = LucideIcons.folderOutput200;
  static const archive = LucideIcons.archive200;
  static const drag = LucideIcons.gripVertical200;
  static const paneDrag = LucideIcons.gripHorizontal200;
  static const arrange = LucideIcons.layoutPanelTop200;
  static const close = LucideIcons.x200;
  static const trash = LucideIcons.trash2200;
  static const search = LucideIcons.search200;
  static const colorWheel = LucideIcons.palette200;
  static const calendar = LucideIcons.calendar200;

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
  });

  final IconData icon;
  final double size;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color:
          color ??
          (enabled
              ? AppColors.text.withValues(alpha: 0.82)
              : AppColors.textHint.withValues(alpha: 0.38)),
    );
  }
}
