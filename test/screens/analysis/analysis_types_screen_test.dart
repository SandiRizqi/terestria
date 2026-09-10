import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/screens/analysis/analysis_types_screen.dart';
import 'package:geoform_app/services/analysis_report_service.dart';

/// Builds a service whose HTTP layer is faked by [handler].
AnalysisReportService _service(
  Future<http.Response> Function() handler,
) {
  return AnalysisReportService(
    getter: (endpoint, {queryParameters}) => handler(),
  );
}

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

Widget _wrap(AnalysisReportService service) => MaterialApp(
      home: AnalysisTypesScreen(service: service),
    );

void main() {
  testWidgets('shows a loading spinner while fetching', (tester) async {
    final service = _service(
      () => Future.delayed(
        const Duration(seconds: 1),
        () => _ok({'success': true, 'data': []}),
      ),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pump(); // first frame, future still pending

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the delayed future complete to avoid pending timer errors.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('renders the analysis types after load', (tester) async {
    final service = _service(() async => _ok({
          'success': true,
          'data': [
            {
              'id': 1,
              'name': 'Analisa Pokok Rapat',
              'code': 'apr',
              'company_count': 3,
            },
            {'id': 2, 'name': 'Kerapatan', 'code': 'krp', 'company_count': 1},
          ],
        }));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Analisa Pokok Rapat'), findsOneWidget);
    expect(find.text('Kerapatan'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets); // company_count shown
  });

  testWidgets('shows an empty state when there are no types', (tester) async {
    final service = _service(() async => _ok({'success': true, 'data': []}));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ada'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    var calls = 0;
    final service = _service(() async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'success': false, 'detail': 'server error'}),
          500,
        );
      }
      return _ok({'success': true, 'data': []});
    });

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Coba lagi'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2); // retry re-invoked the service
  });

  testWidgets('search filters the types client-side', (tester) async {
    final service = _service(() async => _ok({
          'success': true,
          'data': [
            {'id': 1, 'name': 'Analisa Pokok Rapat', 'code': 'apr'},
            {'id': 2, 'name': 'Kerapatan', 'code': 'krp'},
          ],
        }));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    // Keduanya tampil sebelum difilter.
    expect(find.text('Analisa Pokok Rapat'), findsOneWidget);
    expect(find.text('Kerapatan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kerap');
    await tester.pumpAndSettle();

    expect(find.text('Kerapatan'), findsOneWidget);
    expect(find.text('Analisa Pokok Rapat'), findsNothing);
  });

  testWidgets('search with no match shows an empty-result view',
      (tester) async {
    final service = _service(() async => _ok({
          'success': true,
          'data': [
            {'id': 1, 'name': 'Kerapatan', 'code': 'krp'},
          ],
        }));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyz-tidak-ada');
    await tester.pumpAndSettle();

    expect(find.textContaining('Tidak ada hasil'), findsOneWidget);
    expect(find.text('Kerapatan'), findsNothing);
  });
}
