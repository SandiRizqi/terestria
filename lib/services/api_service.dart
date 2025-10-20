import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';

/// Service untuk handle semua HTTP requests dengan token otomatis
/// 
/// Contoh penggunaan:
/// ```dart
/// // GET request
/// final response = await ApiService().get('/api/data');
/// 
/// // POST request
/// final response = await ApiService().post('/api/data', body: {'key': 'value'});
/// 
/// // PUT request
/// final response = await ApiService().put('/api/data/1', body: {'key': 'value'});
/// 
/// // DELETE request
/// final response = await ApiService().delete('/api/data/1');
/// ```
class ApiService {
  final AuthService _authService = AuthService();

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Membuat headers dengan token authorization otomatis
  Future<Map<String, String>> _getHeaders({Map<String, String>? additionalHeaders}) async {
    final headers = Map<String, String>.from(ApiConfig.defaultHeaders);
    
    // Tambahkan token jika ada
    final token = await _authService.getToken();
    if (token != null) {
      headers['Authorization'] = 'Token $token'; // Sesuaikan format dengan backend Anda
      // Jika backend pakai Bearer token, ganti dengan: headers['Authorization'] = 'Bearer $token';
    }
    
    // Tambahkan headers tambahan jika ada
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    
    return headers;
  }

  /// GET request
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    String url = '${ApiConfig.baseUrl}$endpoint';
    
    // Tambahkan query parameters jika ada
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final queryString = Uri(queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      )).query;
      url = '$url?$queryString';
    }

    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: requestHeaders,
      ).timeout(ApiConfig.connectionTimeout);
      
      return response;
    } catch (e) {
      throw ApiException('GET request failed: $e');
    }
  }

  /// POST request
  Future<http.Response> post(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final url = '${ApiConfig.baseUrl}$endpoint';
    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: requestHeaders,
        body: body is String ? body : jsonEncode(body),
      ).timeout(ApiConfig.connectionTimeout);
      
      return response;
    } catch (e) {
      throw ApiException('POST request failed: $e');
    }
  }

  /// PUT request
  Future<http.Response> put(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final url = '${ApiConfig.baseUrl}$endpoint';
    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: requestHeaders,
        body: body is String ? body : jsonEncode(body),
      ).timeout(ApiConfig.connectionTimeout);
      
      return response;
    } catch (e) {
      throw ApiException('PUT request failed: $e');
    }
  }

  /// PATCH request
  Future<http.Response> patch(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final url = '${ApiConfig.baseUrl}$endpoint';
    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    
    try {
      final response = await http.patch(
        Uri.parse(url),
        headers: requestHeaders,
        body: body is String ? body : jsonEncode(body),
      ).timeout(ApiConfig.connectionTimeout);
      
      return response;
    } catch (e) {
      throw ApiException('PATCH request failed: $e');
    }
  }

  /// DELETE request
  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final url = '${ApiConfig.baseUrl}$endpoint';
    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    
    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: requestHeaders,
        body: body != null ? (body is String ? body : jsonEncode(body)) : null,
      ).timeout(ApiConfig.connectionTimeout);
      
      return response;
    } catch (e) {
      throw ApiException('DELETE request failed: $e');
    }
  }

  /// Upload file dengan multipart
  Future<http.StreamedResponse> uploadFile(
    String endpoint, {
    required String filePath,
    required String fileFieldName,
    Map<String, String>? fields,
    Map<String, String>? headers,
  }) async {
    final url = '${ApiConfig.baseUrl}$endpoint';
    final request = http.MultipartRequest('POST', Uri.parse(url));
    
    // Tambahkan headers
    final requestHeaders = await _getHeaders(additionalHeaders: headers);
    request.headers.addAll(requestHeaders);
    
    // Tambahkan file
    request.files.add(await http.MultipartFile.fromPath(fileFieldName, filePath));
    
    // Tambahkan fields lain jika ada
    if (fields != null) {
      request.fields.addAll(fields);
    }
    
    try {
      final response = await request.send();
      return response;
    } catch (e) {
      throw ApiException('File upload failed: $e');
    }
  }

  /// Helper untuk parse response JSON
  Map<String, dynamic> parseResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        'Request failed with status ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Helper untuk check apakah response sukses
  bool isSuccess(http.Response response) {
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}

/// Custom exception untuk API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}
