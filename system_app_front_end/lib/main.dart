import 'package:flutter/material.dart';

import './app.dart';
import './shared/utils/hardware_keyboard_guard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installHardwareKeyboardGuard();
  runApp(const SystemApp());
}
