import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/analysis/paginated_response.dart';

void main() {
  group('PaginatedResponse.fromJson', () {
    test('parses wrapper and maps data via item parser', () {
      final json = {
        'success': true,
        'page': 1,
        'page_size': 10,
        'total_pages': 5,
        'total_count': 42,
        'data': [
          {'v': 1},
          {'v': 2},
        ],
      };

      final res = PaginatedResponse<int>.fromJson(
        json,
        (item) => (item as Map<String, dynamic>)['v'] as int,
      );

      expect(res.success, isTrue);
      expect(res.page, 1);
      expect(res.pageSize, 10);
      expect(res.totalPages, 5);
      expect(res.totalCount, 42);
      expect(res.data, [1, 2]);
    });

    test('hasMore is true when current page precedes total pages', () {
      final res = PaginatedResponse<int>.fromJson(
        {'page': 2, 'total_pages': 5, 'data': []},
        (item) => item as int,
      );
      expect(res.hasMore, isTrue);
    });

    test('hasMore is false on the last page', () {
      final res = PaginatedResponse<int>.fromJson(
        {'page': 5, 'total_pages': 5, 'data': []},
        (item) => item as int,
      );
      expect(res.hasMore, isFalse);
    });

    test('handles empty/absent data safely with defaults', () {
      final res = PaginatedResponse<int>.fromJson(
        {'success': true},
        (item) => item as int,
      );

      expect(res.data, isEmpty);
      expect(res.page, 1);
      expect(res.totalPages, 1);
      expect(res.totalCount, 0);
      expect(res.hasMore, isFalse);
    });
  });
}
