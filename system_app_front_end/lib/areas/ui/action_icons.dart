import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The icon vocabulary a saved AI action can choose from.
///
/// A stored action keeps the **key**, never a code point, so this list can grow
/// or swap an icon without touching rows in the database. Same Lucide stroke
/// weight as the bottom bar, because that is where the icons end up.
const defaultActionIconKey = 'sparkles';

const _actionIcons = <String, IconData>{
  // Thinking
  'sparkles': LucideIcons.sparkles200,
  'wand': LucideIcons.wandSparkles200,
  'zap': LucideIcons.zap200,
  'brain': LucideIcons.brain200,
  'lightbulb': LucideIcons.lightbulb200,
  'target': LucideIcons.target200,
  // Writing
  'pen': LucideIcons.penLine200,
  'highlight': LucideIcons.highlighter200,
  'spellcheck': LucideIcons.spellCheck200,
  'quote': LucideIcons.quote200,
  'languages': LucideIcons.languages200,
  'note': LucideIcons.stickyNote200,
  // Structure
  'checklist': LucideIcons.listChecks200,
  'todo': LucideIcons.listTodo200,
  'table': LucideIcons.table2200,
  'chart': LucideIcons.chartLine200,
  'pie': LucideIcons.chartPie200,
  'clipboard': LucideIcons.clipboardList200,
  // Rhythm
  'calendar': LucideIcons.calendarClock200,
  'bell': LucideIcons.bell200,
  'inbox': LucideIcons.inbox200,
  'send': LucideIcons.send200,
  'tags': LucideIcons.tags200,
  'star': LucideIcons.star200,
  // Work
  'briefcase': LucideIcons.briefcase200,
  'folder': LucideIcons.folder200,
  'files': LucideIcons.files200,
  'search': LucideIcons.search200,
  'filter': LucideIcons.filter200,
  'link': LucideIcons.link200,
  // Making
  'code': LucideIcons.code200,
  'terminal': LucideIcons.terminal200,
  'layers': LucideIcons.layers200,
  'package': LucideIcons.package200,
  'wrench': LucideIcons.wrench200,
  'puzzle': LucideIcons.puzzle200,
  // Living
  'heart': LucideIcons.heart200,
  'workout': LucideIcons.dumbbell200,
  'coffee': LucideIcons.coffee200,
  'meal': LucideIcons.utensils200,
  'leaf': LucideIcons.leaf200,
  'moon': LucideIcons.moon200,
  // Time and place
  'timer': LucideIcons.timer200,
  'history': LucideIcons.history200,
  'hourglass': LucideIcons.hourglass200,
  'place': LucideIcons.mapPin200,
  'route': LucideIcons.route200,
  'sun': LucideIcons.sun200,
  // People and worth
  'people': LucideIcons.users200,
  'message': LucideIcons.messageSquare200,
  'megaphone': LucideIcons.megaphone200,
  'gift': LucideIcons.gift200,
  'wallet': LucideIcons.wallet200,
  'trophy': LucideIcons.trophy200,
};

/// Every key, in the order the picker shows them.
List<String> get actionIconKeys => _actionIcons.keys.toList();

/// The icon for a stored key — sparkles for an empty or retired one, so an
/// action always has a face.
IconData actionIcon(String? key) =>
    _actionIcons[key] ?? _actionIcons[defaultActionIconKey]!;
