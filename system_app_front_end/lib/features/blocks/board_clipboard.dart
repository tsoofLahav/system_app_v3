import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../shared/utils/clipboard_image.dart';
import 'board_content.dart';

const boardClipMagic = 'system_app:board_item:v1:';

Future<void> copyBoardItemToClipboard({
  required BoardItem item,
  required String imageUrl,
}) async {
  final payload = '$boardClipMagic${jsonEncode(item.toJson())}';
  await Clipboard.setData(ClipboardData(text: payload));
  try {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      await writeClipboardImageBytes(response.bodyBytes);
    }
  } catch (_) {
    // Text payload still allows paste within the app.
  }
}

BoardItem? boardItemFromClipboardText(String? text) {
  if (text == null || !text.startsWith(boardClipMagic)) return null;
  try {
    final decoded = jsonDecode(text.substring(boardClipMagic.length));
    if (decoded is! Map) return null;
    return BoardItem.fromJson(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return null;
  }
}

Future<BoardItem?> boardItemFromSystemClipboard() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return boardItemFromClipboardText(data?.text);
}

Future<Uint8List?> clipboardImageBytes() => readClipboardImageBytes();
