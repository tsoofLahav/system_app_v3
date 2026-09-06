import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<dynamic> get(String path) async {
    final response = await _client.get(_uri(path));
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await _client.put(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<void> delete(String path, {Map<String, dynamic>? body}) async {
    final response = await _client.delete(
      _uri(path),
      headers: body == null ? null : {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode == 204) return;
    _decode(response);
  }

  Future<Map<String, dynamic>> uploadImage(String filePath, List<int> bytes) async {
    final request = http.MultipartRequest('POST', _uri('/upload-image'));
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filePath),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response);
    return Map<String, dynamic>.from(data as Map);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    String message = 'Request failed (${response.statusCode})';
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
        message = body['error']?.toString() ?? message;
      }
    } catch (_) {}
    throw ApiException(
      message,
      statusCode: response.statusCode,
      body: body,
    );
  }
}
