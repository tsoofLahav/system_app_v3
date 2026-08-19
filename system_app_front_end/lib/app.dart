import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import './areas/ui/app_theme.dart';
import './core/app_state.dart';
import './core/l10n/app_language.dart';
import './areas/ux/shell/app_shell.dart';

class SystemApp extends StatelessWidget {
  const SystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: const _SystemAppView(),
    );
  }
}

/// Rebuilds [MaterialApp] only when language (theme / direction) changes.
///
/// A `Consumer<AppState>` around the whole app remounts the file editor on
/// every `notifyListeners` and desyncs [HardwareKeyboard] while typing
/// (`KeyDownEvent … already pressed`).
class _SystemAppView extends StatefulWidget {
  const _SystemAppView();

  @override
  State<_SystemAppView> createState() => _SystemAppViewState();
}

class _SystemAppViewState extends State<_SystemAppView> {
  late final AppState _state;
  late AppLanguage _language;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _language = _state.language;
    _state.addListener(_onState);
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (_state.language == _language || !mounted) return;
    setState(() => _language = _state.language);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'system_app',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_language),
      builder: (context, child) {
        return Directionality(
          textDirection: _state.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AppShell(state: _state),
    );
  }
}
