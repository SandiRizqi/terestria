import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';
import 'crashlytics_service.dart';

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

  /// HTTP client. Diinjeksi hanya untuk pengujian (mis. MockClient); produksi
  /// memakai client default.
  final http.Client _client;

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() : _client = http.Client();

  /// Konstruktor untuk pengujian: memungkinkan injeksi [http.Client].
  ApiService.forTest({http.Client? client}) : _client = client ?? http.Client();

  /// Deteksi apakah sebuah error berasal dari masalah koneksi/DNS/timeout.
  /// `http.ClientException` membungkus `SocketException` (mis. "Failed host
  /// lookup"), jadi kita periksa tipe & isi pesannya.
  static bool _isConnectionError(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is http.ClientException) {
      final msg = e.message.toLowerCase();
      return msg.contains('failed host lookup') ||
          msg.contains('socketexception') ||
          msg.contains('connection closed') ||
          msg.contains('connection refused') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection reset');
    }
    return false;
  }

  /// Bangun ApiException yang sudah terklasifikasi dari error mentah.
  static ApiException _buildApiException(String method, Object e) {
    if (_isConnectionError(e)) {
      return ApiException(
        'Tidak ada koneksi ke server',
        isConnectionError: true,
      );
    }
    return ApiException('$method request failed: $e');
  }

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
    } catch (e, stack) {
      crashlytics.setContext('http_method', 'GET');
      crashlytics.setContext('endpoint', endpoint);
      crashlytics.recordError(e, stack, reason: 'API: GET request failed');
      throw _buildApiException('GET', e);
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
    } catch (e, stack) {
      crashlytics.setContext('http_method', 'POST');
      crashlytics.setContext('endpoint', endpoint);
      crashlytics.recordError(e, stack, reason: 'API: POST request failed');
      throw _buildApiException('POST', e);
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
    } catch (e, stack) {
      crashlytics.setContext('http_method', 'PUT');
      crashlytics.setContext('endpoint', endpoint);
      crashlytics.recordError(e, stack, reason: 'API: PUT request failed');
      throw _buildApiException('PUT', e);
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
      throw _buildApiException('PATCH', e);
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
    } catch (e, stack) {
      crashlytics.setContext('http_method', 'DELETE');
      crashlytics.setContext('endpoint', endpoint);
      crashlytics.recordError(e, stack, reason: 'API: DELETE request failed');
      throw _buildApiException('DELETE', e);
    }
  }

  /// Upload file dengan multipart (legacy method)
  Future<http.StreamedResponse> uploadFileStream(
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

  /// Upload file dan return parsed response.
  ///
  /// Mengembalikan `null` bila upload gagal (tipe file salah, non-2xx, timeout,
  /// atau error jaringan) — kegagalan dilaporkan ke Crashlytics dengan konteks
  /// nama file & status, bukan sekadar `print`. [timeout] default ke
  /// [ApiConfig.uploadTimeout] supaya upload tidak menggantung tanpa batas.
  Future<Map<String, dynamic>?> uploadFile(
    String url,
    dynamic file, {
    String fileFieldName = 'file',
    Map<String, String>? fields,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    // Handle different file types
    String? filePath;
    if (file is String) {
      filePath = file;
    } else if (file is File) {
      filePath = file.path;
    }

    if (filePath == null) {
      crashlytics.recordError(
        ApiException('Invalid file type'),
        StackTrace.current,
        reason: 'API: photo upload invalid file type',
      );
      return null;
    }

    final fileName = filePath.split('/').last;

    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Tambahkan headers dengan token
      final requestHeaders = await _getHeaders(additionalHeaders: headers);
      request.headers.addAll(requestHeaders);

      // Tambahkan file
      request.files.add(await http.MultipartFile.fromPath(fileFieldName, filePath));

      // Tambahkan fields lain jika ada
      if (fields != null) {
        request.fields.addAll(fields);
      }

      // Send request (dengan timeout supaya tidak menggantung)
      final streamedResponse = await _client
          .send(request)
          .timeout(timeout ?? ApiConfig.uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }

      crashlytics.recordError(
        ApiException('Photo upload failed', statusCode: response.statusCode),
        StackTrace.current,
        reason: 'API: photo upload non-2xx',
        information: ['file: $fileName', 'status: ${response.statusCode}'],
      );
      return null;
    } catch (e, stack) {
      crashlytics.recordError(
        e,
        stack,
        reason: 'API: photo upload failed',
        information: ['file: $fileName'],
      );
      return null;
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

  /// True bila error disebabkan masalah koneksi/DNS/timeout (bukan error
  /// server). Dipakai lapisan sync untuk membedakan "tidak ada koneksi"
  /// dari error lain, sehingga bisa berhenti rapi & beri pesan ramah.
  final bool isConnectionError;

  ApiException(this.message, {this.statusCode, this.isConnectionError = false});

  @override
  String toString() => 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}
