import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True on native iOS (including iPad for v1).
bool get isPhoneLayout => !kIsWeb && Platform.isIOS;
