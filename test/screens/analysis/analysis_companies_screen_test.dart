import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/screens/analysis/analysis_companies_screen.dart';
import 'package:geoform_app/services/analysis_report_service.dart';

typedef _Handler = Future<http.Response> Function(
    String endpoint, Map<String, dynamic>? query);

AnalysisReportService _service(_Handler handler) => AnalysisReportService(
      getter: (endpoint, {queryParameters}) =>
          handler(endpoint, queryParameters),
    );

http.Response _companiesPage({
  required int page,
  required int totalPages,
  required List<String> names,
}) {
  return http.Response(
    jsonEncode({
      'success': true,
      'page': page,
      'page_size': 10,
      'total_pages': totalPages,
      'total_count': totalPages * 10,
      'data': [
        for (var i = 0; i < names.length; i++)
          {
            'company_id': page * 100 + i,
            'comp_name': names[i],
            'comp_code': 'C$i',
            'comp_group': 'TAP',
            'file_count': 5,
          },
      ],
    }),
    200,
  );
}

Widget _wrap(AnalysisReportService service) => MaterialApp(
      home: AnalysisCompaniesScreen(
        typeCode: 'krp',
        typeName: 'Kerapatan',
        service: service,
      ),
    );

void main() {
  testWidgets('renders the first page of PTs', (tester) async {
    final service = _service((endpoint, query) async {
      return _companiesPage(page: 1, totalPages: 1, names: ['PT NPN', 'PT ABC']);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('PT NPN'), findsOneWidget);
    expect(find.text('PT ABC'), findsOneWidget);
  });

  testWidgets('shows empty state when no PTs', (tester) async {
    final service = _service((endpoint, query) async {
      return _companiesPage(page: 1, totalPages: 1, names: []);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ada'), findsOneWidget);
  });

  testWidgets('shows error + retry on failure', (tester) async {
    var calls = 0;
    final service = _service((endpoint, query) async {
      calls++;
      if (calls == 1) {
        return http.Response(
            jsonEncode({'success': false, 'detail': 'boom'}), 500);
      }
      return _companiesPage(page: 1, totalPages: 1, names: ['PT NPN']);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Coba lagi'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('PT NPN'), findsOneWidget);
  });

  testWidgets('typing in search triggers a server-side search', (tester) async {
    final searches = <String?>[];
    final service = _service((endpoint, query) async {
      searches.add(query?['search'] as String?);
      final q = query?['search'] as String?;
      return _companiesPage(
        page: 1,
        totalPages: 1,
        names: q == 'NPN' ? ['PT NPN'] : ['PT NPN', 'PT ABC'],
      );
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('PT ABC'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'NPN');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();

    expect(searches.contains('NPN'), isTrue);
    expect(find.text('PT ABC'), findsNothing);
    expect(find.text('PT NPN'), findsOneWidget);
  });

  testWidgets('loads and appends the next page on scroll', (tester) async {
    final pagesRequested = <int>[];
    final service = _service((endpoint, query) async {
      final page = int.parse(query?['page'] as String? ?? '1');
      pagesRequested.add(page);
      return _companiesPage(
        page: page,
        totalPages: 2,
        names: List.generate(12, (i) => 'PT p${page}_$i'),
      );
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('PT p1_0'), findsOneWidget);

    // Scroll the list to the bottom to trigger loading page 2.
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(pagesRequested.contains(2), isTrue);

    // A page-2 item is now part of the list (reveal it by scrolling further).
    await tester.scrollUntilVisible(
      find.text('PT p2_0'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PT p2_0'), findsOneWidget);
  });
}
