import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'design_system/app_theme.dart';
import 'core/app_state.dart';
import 'features/shell/app_shell.dart';

class SystemApp extends StatelessWidget {
  const SystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'system_app',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(state.language),
            builder: (context, child) {
              return Directionality(
                textDirection: state.textDirection,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: AppShell(state: state),
          );
        },
      ),
    );
  }
}
