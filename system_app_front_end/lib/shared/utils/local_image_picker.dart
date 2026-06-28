import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Opens the OS image picker after a short delay (e.g. after a menu closes).
Future<(String, List<int>)?> pickLocalImageFile({Duration delay = const Duration(milliseconds: 80)}) async {
  await Future<void>.delayed(delay);

  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  final file = result != null && result.files.isNotEmpty
      ? result.files.first
      : null;
  if (file == null || file.name.isEmpty) return null;

  final bytes = file.bytes ?? await _readBytesFromPath(file.path);
  if (bytes == null || bytes.isEmpty) return null;
  return (file.name, bytes);
}

Future<List<int>?> _readBytesFromPath(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
