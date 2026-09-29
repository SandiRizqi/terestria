import '../models/cloud_basemap_model.dart';
import 'api_service.dart';

import '../utils/app_logger.dart';
/// Service untuk mengambil daftar basemap dari cloud
class CloudBasemapService {
  final ApiService _apiService = ApiService();
  
  // Singleton pattern
  static final CloudBasemapService _instance = CloudBasemapService._internal();
  factory CloudBasemapService() => _instance;
  CloudBasemapService._internal();

  /// Fetch basemap list dari cloud
  /// Endpoint: /mobile/tms-layers/
  Future<CloudBasemapResponse?> fetchCloudBasemaps() async {
    try {
      final response = await _apiService.get('/mobile/tms-layers/');
      
      if (_apiService.isSuccess(response)) {
        final parsed = _apiService.parseResponse(response);
        return CloudBasemapResponse.fromJson(parsed);
      } else {
        logWarn('Failed to fetch cloud basemaps: ${response.statusCode}', tag: 'BASEMAP');
        return null;
      }
    } catch (e) {
      logWarn('Error fetching cloud basemaps: $e', tag: 'BASEMAP');
      return null;
    }
  }
}
