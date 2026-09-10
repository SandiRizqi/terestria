import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/services/analysis_report_service.dart';

/// Fake getter matching [ApiGetter]; records the last call and returns a canned
/// response so we can assert both the request shape and the parsing.
class _FakeApi {
  String? lastEndpoint;
  Map<String, dynamic>? lastQuery;
  http.Response response;

  _FakeApi(this.response);

  Future<http.Response> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastEndpoint = endpoint;
    lastQuery = queryParameters;
    return response;
  }
}

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  group('fetchAnalysisTypes', () {
    test('hits the types endpoint and parses the data list', () async {
      final fake = _FakeApi(_ok({
        'success': true,
        'data': [
          {'id': 1, 'name': 'Kerapatan', 'code': 'kerapatan', 'company_count': 3},
        ],
      }));
      final service = AnalysisReportService(getter: fake.get);

      final types = await service.fetchAnalysisTypes();

      expect(fake.lastEndpoint, '/api/palmanalisis/types/');
      expect(types, hasLength(1));
      expect(types.first.code, 'kerapatan');
      expect(types.first.companyCount, 3);
    });
  });

  group('fetchCompanies', () {
    test('builds paginated + search + include_empty query and parses', () async {
      final fake = _FakeApi(_ok({
        'success': true,
        'page': 1,
        'page_size': 10,
        'total_pages': 2,
        'total_count': 12,
        'data': [
          {
            'company_id': 20,
            'comp_name': 'PT NPN',
            'comp_code': 'NPN',
            'comp_group': 'TAP',
            'file_count': 16,
          },
        ],
      }));
      final service = AnalysisReportService(getter: fake.get);

      final res = await service.fetchCompanies(
        'kerapatan',
        page: 1,
        search: 'NPN',
        includeEmpty: true,
      );

      expect(fake.lastEndpoint, '/api/palmanalisis/types/kerapatan/companies/');
      expect(fake.lastQuery!['page'], '1');
      expect(fake.lastQuery!['page_size'], '10');
      expect(fake.lastQuery!['search'], 'NPN');
      expect(fake.lastQuery!['include_empty'], 'true');
      expect(res.totalPages, 2);
      expect(res.hasMore, isTrue);
      expect(res.data.first.compName, 'PT NPN');
    });

    test('omits search and include_empty when not requested', () async {
      final fake = _FakeApi(_ok({'success': true, 'data': []}));
      final service = AnalysisReportService(getter: fake.get);

      await service.fetchCompanies('kerapatan', page: 2);

      expect(fake.lastQuery!.containsKey('search'), isFalse);
      expect(fake.lastQuery!.containsKey('include_empty'), isFalse);
      expect(fake.lastQuery!['page'], '2');
    });
  });

  group('fetchFiles', () {
    test('builds query with block_code + ordering and parses FileRows', () async {
      final fake = _FakeApi(_ok({
        'success': true,
        'page': 1,
        'page_size': 10,
        'total_pages': 1,
        'total_count': 1,
        'data': [
          {
            'id': 12,
            'title': 'Peta_G03.pdf',
            'block_code': 'G03',
            'file_name': 'Peta_G03.pdf',
            'download_url': 'https://signed/u',
            'content_type': 'application/pdf',
          },
        ],
      }));
      final service = AnalysisReportService(getter: fake.get);

      final res = await service.fetchFiles(
        'kerapatan',
        20,
        search: 'Peta',
        blockCode: 'G03',
        ordering: '-created_at',
      );

      expect(
        fake.lastEndpoint,
        '/api/palmanalisis/types/kerapatan/companies/20/files/',
      );
      expect(fake.lastQuery!['search'], 'Peta');
      expect(fake.lastQuery!['block_code'], 'G03');
      expect(fake.lastQuery!['ordering'], '-created_at');
      expect(res.data.first.isPdf, isTrue);
      expect(res.data.first.blockCode, 'G03');
    });
  });

  group('fetchFileDetail', () {
    test('parses the wrapped FileRow (for refreshing download_url)', () async {
      final fake = _FakeApi(_ok({
        'success': true,
        'data': {
          'id': 12,
          'title': 'Peta_G03.pdf',
          'file_name': 'Peta_G03.pdf',
          'download_url': 'https://signed/fresh',
        },
      }));
      final service = AnalysisReportService(getter: fake.get);

      final file = await service.fetchFileDetail(12);

      expect(fake.lastEndpoint, '/api/palmanalisis/files/12/');
      expect(file.downloadUrl, 'https://signed/fresh');
    });
  });

  group('error handling', () {
    test('throws AnalysisApiException with server detail on non-2xx', () async {
      final fake = _FakeApi(
        http.Response(jsonEncode({'success': false, 'detail': 'not in scope'}), 404),
      );
      final service = AnalysisReportService(getter: fake.get);

      expect(
        () => service.fetchFileDetail(99),
        throwsA(
          isA<AnalysisApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('not in scope')),
        ),
      );
    });
  });
}
