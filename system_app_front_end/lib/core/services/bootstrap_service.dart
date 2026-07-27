import './api_service.dart';

class BootstrapService {
  BootstrapService(this._api);

  final ApiService _api;

  Future<Map<String, dynamic>> bootstrap() async {
    final data = await _api.post('/bootstrap', {}) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> status() async {
    final data = await _api.get('/bootstrap/status') as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
