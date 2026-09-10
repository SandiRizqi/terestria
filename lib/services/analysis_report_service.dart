import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/analysis/analysis_type_model.dart';
import '../models/analysis/analysis_company_model.dart';
import '../models/analysis/analysis_file_model.dart';
import '../models/analysis/paginated_response.dart';
import 'api_service.dart';

/// Signature dari GET yang dipakai service ini. Cocok dengan
/// [ApiService.get] (yang punya named param opsional tambahan `headers`),
/// dan bisa diganti fake saat testing.
typedef ApiGetter = Future<http.Response> Function(
  String endpoint, {
  Map<String, dynamic>? queryParameters,
});

/// Service untuk endpoint PalmAnalisis (Analysis Report).
///
/// Hierarki: Jenis Analisis -> Project/PT -> File. Semua request lewat token
/// yang sudah dikelola [ApiService]. Base host = [ApiConfig.baseUrl].
class AnalysisReportService {
  final ApiGetter _get;

  AnalysisReportService({ApiGetter? getter}) : _get = getter ?? ApiService().get;

  /// #3 Daftar Jenis Analisis (non-paginated).
  Future<List<AnalysisType>> fetchAnalysisTypes() async {
    final response = await _get(ApiConfig.analysisTypesEndpoint);
    final json = _decode(response);
    final list = json['data'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AnalysisType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// #4 Daftar Project (PT) untuk satu jenis — paginated + search.
  Future<PaginatedResponse<AnalysisCompany>> fetchCompanies(
    String typeCode, {
    int page = 1,
    int pageSize = 10,
    String? search,
    bool includeEmpty = false,
  }) async {
    final query = <String, dynamic>{
      'page': '$page',
      'page_size': '$pageSize',
      if (search != null && search.isNotEmpty) 'search': search,
      if (includeEmpty) 'include_empty': 'true',
    };
    final response = await _get(
      ApiConfig.analysisCompaniesEndpoint(typeCode),
      queryParameters: query,
    );
    return PaginatedResponse<AnalysisCompany>.fromJson(
      _decode(response),
      (item) => AnalysisCompany.fromJson(item as Map<String, dynamic>),
    );
  }

  /// #5 Daftar File untuk satu jenis x PT — paginated + search + block_code.
  Future<PaginatedResponse<AnalysisFile>> fetchFiles(
    String typeCode,
    int companyId, {
    int page = 1,
    int pageSize = 10,
    String? search,
    String? blockCode,
    String? ordering,
  }) async {
    final query = <String, dynamic>{
      'page': '$page',
      'page_size': '$pageSize',
      if (search != null && search.isNotEmpty) 'search': search,
      if (blockCode != null && blockCode.isNotEmpty) 'block_code': blockCode,
      if (ordering != null && ordering.isNotEmpty) 'ordering': ordering,
    };
    final response = await _get(
      ApiConfig.analysisFilesEndpoint(typeCode, companyId),
      queryParameters: query,
    );
    return PaginatedResponse<AnalysisFile>.fromJson(
      _decode(response),
      (item) => AnalysisFile.fromJson(item as Map<String, dynamic>),
    );
  }

  /// #6 Detail file — dipakai untuk me-refresh `download_url` yang kedaluwarsa.
  Future<AnalysisFile> fetchFileDetail(int fileId) async {
    final response = await _get(ApiConfig.analysisFileDetailEndpoint(fileId));
    final json = _decode(response);
    return AnalysisFile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Decode body sukses; lempar [AnalysisApiException] untuk status non-2xx.
  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String detail = 'Request failed (${response.statusCode})';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) {
        detail = body['detail'].toString();
      }
    } catch (_) {
      // Body bukan JSON — pakai pesan default.
    }
    throw AnalysisApiException(detail, response.statusCode);
  }
}

/// Error dari endpoint PalmAnalisis (mengikuti `{success:false, detail:"..."}`).
class AnalysisApiException implements Exception {
  final String message;
  final int statusCode;

  AnalysisApiException(this.message, this.statusCode);

  @override
  String toString() => 'AnalysisApiException($statusCode): $message';
}
