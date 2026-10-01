import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/screens/project/widgets/filter_option_chips.dart';

/// Chip pilihan di panel filter daftar data (dropdown, pilihan ganda, skala):
/// pilih satu, ketuk lagi untuk melepas.

Future<List<String?>> _pump(WidgetTester tester,
    {required List<String> values,
    String? selected,
    String Function(String)? labelOf}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final changes = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FilterOptionChips(
        values: values,
        selected: selected,
        labelOf: labelOf,
        onChanged: changes.add,
      ),
    ),
  ));
  return changes;
}

void main() {
  testWidgets('ketuk opsi → terpilih; ketuk yang terpilih → dilepas',
      (tester) async {
    var changes = await _pump(tester, values: ['Ulat api', 'Tikus']);
    await tester.tap(find.text('Tikus'));
    expect(changes, ['Tikus']);

    changes = await _pump(tester, values: ['Ulat api', 'Tikus'], selected: 'Tikus');
    await tester.tap(find.text('Tikus'));
    expect(changes, [null]);
  });

  testWidgets('label bisa diatur (skala 1–5); opsi banyak muat di 360 dp',
      (tester) async {
    final changes = await _pump(tester,
        values: ['1', '2', '3', '4', '5'], labelOf: (v) => '$v ★');
    expect(find.text('4 ★'), findsOneWidget);
    await tester.tap(find.text('4 ★'));
    expect(changes, ['4']);

    await _pump(tester, values: [for (var i = 0; i < 12; i++) 'Opsi panjang $i']);
    expect(tester.takeException(), isNull);
  });
}
