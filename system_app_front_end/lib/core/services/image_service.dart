import 'api_service.dart';

class ImageService {
  ImageService(this._api);

  final ApiService _api;

  Future<Map<String, dynamic>> uploadBytes(String filename, List<int> bytes) {
    return _api.uploadImage(filename, bytes);
  }
}
