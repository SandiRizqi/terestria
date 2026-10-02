import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/widgets/collection/accuracy_summary.dart';

/// Ringkasan akurasi record dibanding batas project (SPEC §3.6): peringatan
/// bila melebihi, tetapi simpan tetap boleh (line/polygon).

GeoPoint _p(double? accuracy) => GeoPoint(
    latitude: -6.2, longitude: 106.8, accuracy: accuracy, timestamp: DateTime(2026));

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
  ));
}

void main() {
  testWidgets('rata-rata di atas batas → peringatan, server akan menolak',
      (tester) async {
    await _pump(
        tester,
        AccuracySummary(
            geometryType: GeometryType.polygon,
            points: [_p(9), _p(7.8), _p(0)],
            limit: 5));
    expect(find.text('Average GPS accuracy 8.4 m — project limit 5 m'), findsOneWidget);
    expect(find.textContaining('server will reject'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dalam batas → info tanpa peringatan', (tester) async {
    await _pump(
        tester,
        AccuracySummary(
            geometryType: GeometryType.line, points: [_p(3), _p(4)], limit: 5));
    expect(find.text('Average GPS accuracy 3.5 m — project limit 5 m'), findsOneWidget);
    expect(find.textContaining('server will reject'), findsNothing);
  });

  testWidgets('tanpa titik GPS atau tanpa batas → tidak tampil', (tester) async {
    await _pump(
        tester,
        AccuracySummary(
            geometryType: GeometryType.line, points: [_p(0), _p(0)], limit: 5));
    expect(find.textContaining('accuracy'), findsNothing);
    await _pump(
        tester,
        AccuracySummary(geometryType: GeometryType.line, points: [_p(9)], limit: null));
    expect(find.textContaining('accuracy'), findsNothing);
  });
}
