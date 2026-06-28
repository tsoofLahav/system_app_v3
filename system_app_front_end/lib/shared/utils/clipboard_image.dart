import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('system_app/clipboard_image');

/// Reads PNG/JPEG (or other image) bytes from the system clipboard.
Future<Uint8List?> readClipboardImageBytes() async {
  if (!Platform.isMacOS) return null;
  try {
    final data = await _channel.invokeMethod<Object>('readImage');
    if (data is Uint8List && data.isNotEmpty) return data;
  } on MissingPluginException {
    return null;
  } catch (_) {
    return null;
  }
  return null;
}

/// Writes image bytes to the system clipboard (macOS).
Future<void> writeClipboardImageBytes(Uint8List bytes) async {
  if (!Platform.isMacOS || bytes.isEmpty) return;
  try {
    await _channel.invokeMethod<void>('writeImage', bytes);
  } on MissingPluginException {
    // Clipboard text payload may still be available for in-app paste.
  } catch (_) {}
}
