import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  // Sync single GeoData to backend
  Future<SyncResult> syncGeoData(GeoData geoData, Project project) async {
    try {
      final url = ApiConfig.getFullUrl(ApiConfig.syncDataEndpoint);
      
      // Prepare data untuk dikirim
      final Map<String, dynamic> payload = {
        'id': geoData.id,
        'project_id': geoData.projectId,
        'project_name': project.name,
        'geometry_type': project.geometryType.toString().split('.').last,
        'form_data': geoData.formData,
        'points': geoData.points.map((point) => {
          'latitude': point.latitude,
          'longitude': point.longitude,
        }).toList(),
        'created_at': geoData.createdAt.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse(url),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return SyncResult(
          success: true,
          message: responseData['message'] ?? 'Data synced successfully',
          data: responseData,
        );
      } else {
        return SyncResult(
          success: false,
          message: 'Server error: ${response.statusCode} - ${response.body}',
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timeout',
      );
    } on FormatException catch (e) {
      return SyncResult(
        success: false,
        message: 'Invalid response format: ${e.message}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }

  // Sync multiple GeoData
  Future<BatchSyncResult> syncMultipleGeoData(
    List<GeoData> geoDataList,
    Project project,
  ) async {
    int successCount = 0;
    int failCount = 0;
    List<String> errors = [];

    for (var geoData in geoDataList) {
      final result = await syncGeoData(geoData, project);
      if (result.success) {
        successCount++;
      } else {
        failCount++;
        errors.add('${geoData.id}: ${result.message}');
      }
    }

    return BatchSyncResult(
      total: geoDataList.length,
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  // Test connection to backend
  Future<bool> testConnection() async {
    try {
      final url = ApiConfig.baseUrl;
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 || 
             response.statusCode == 404 || 
             response.statusCode == 401; // Server responds
    } catch (_) {
      return false;
    }
  }
}

// Result classes
class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  SyncResult({
    required this.success,
    required this.message,
    this.data,
  });
}

class BatchSyncResult {
  final int total;
  final int successCount;
  final int failCount;
  final List<String> errors;

  BatchSyncResult({
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.errors,
  });

  bool get hasErrors => failCount > 0;
  bool get allSuccess => successCount == total;
  
  String get summary {
    if (allSuccess) {
      return 'All $total records synced successfully';
    } else if (successCount > 0) {
      return '$successCount of $total records synced. $failCount failed.';
    } else {
      return 'Failed to sync all records';
    }
  }
}
