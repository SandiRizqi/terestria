import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/screens/analysis/analysis_files_screen.dart';
import 'package:geoform_app/services/analysis_report_service.dart';

typedef _Handler = Future<http.Response> Function(
    String endpoint, Map<String, dynamic>? query);

AnalysisReportService _service(_Handler handler) => AnalysisReportService(
      getter: (endpoint, {queryParameters}) =>
          handler(endpoint, queryParameters),
    );

http.Response _filesPage({
  required int page,
  required int totalPages,
  required List<String> titles,
  String contentType = 'application/pdf',
}) {
  return http.Response(
    jsonEncode({
      'success': true,
      'page': page,
      'page_size': 10,
      'total_pages': totalPages,
      'total_count': totalPages * 10,
      'data': [
        for (var i = 0; i < titles.length; i++)
          {
            'id': page * 100 + i,
            'title': titles[i],
            'block_code': 'G0$i',
            'file_name': titles[i],
            'file_size': 1048576,
            'content_type': contentType,
            'download_url': 'https://signed/$i',
          },
      ],
    }),
    200,
  );
}

Widget _wrap(AnalysisReportService service) => MaterialApp(
      home: AnalysisFilesScreen(
        typeCode: 'krp',
        companyId: 20,
        title: 'PT NPN',
        service: service,
      ),
    );

void main() {
  testWidgets('renders files with an Add as Basemap action for PDFs',
      (tester) async {
    final service = _service((endpoint, query) async {
      return _filesPage(page: 1, totalPages: 1, titles: ['Peta_G03.pdf']);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Peta_G03.pdf'), findsOneWidget);
    expect(find.text('Add as Basemap'), findsOneWidget);
  });

  testWidgets('shows empty state when no files', (tester) async {
    final service = _service((endpoint, query) async {
      return _filesPage(page: 1, totalPages: 1, titles: []);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('yet'), findsOneWidget);
  });

  testWidgets('shows error + retry on failure', (tester) async {
    var calls = 0;
    final service = _service((endpoint, query) async {
      calls++;
      if (calls == 1) {
        return http.Response(
            jsonEncode({'success': false, 'detail': 'boom'}), 500);
      }
      return _filesPage(page: 1, totalPages: 1, titles: ['Peta_G03.pdf']);
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Peta_G03.pdf'), findsOneWidget);
  });

  testWidgets('typing in search triggers a server-side search', (tester) async {
    final searches = <String?>[];
    final service = _service((endpoint, query) async {
      searches.add(query?['search'] as String?);
      final q = query?['search'] as String?;
      return _filesPage(
        page: 1,
        totalPages: 1,
        titles: q == 'G03' ? ['Peta_G03.pdf'] : ['Peta_G03.pdf', 'Peta_F10.pdf'],
      );
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('Peta_F10.pdf'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'G03');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(searches.contains('G03'), isTrue);
    expect(find.text('Peta_F10.pdf'), findsNothing);
    expect(find.text('Peta_G03.pdf'), findsOneWidget);
  });

  testWidgets('loads and appends the next page on scroll', (tester) async {
    final pagesRequested = <int>[];
    final service = _service((endpoint, query) async {
      final page = int.parse(query?['page'] as String? ?? '1');
      pagesRequested.add(page);
      return _filesPage(
        page: page,
        totalPages: 2,
        titles: List.generate(12, (i) => 'File p${page}_$i.pdf'),
      );
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('File p1_0.pdf'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(pagesRequested.contains(2), isTrue);
    await tester.scrollUntilVisible(
      find.text('File p2_0.pdf'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('File p2_0.pdf'), findsOneWidget);
  });
}
