import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/widgets/layers/shapefile_picker_dialog.dart';

/// Buka dialog; hasilnya ditulis ke [result] setelah dialog tertutup.
Future<void> _open(
    WidgetTester tester, List<String> names, List<String?> result) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async =>
            result.add(await showShapefilePicker(context, names)),
        child: const Text('buka'),
      ),
    ),
  ));
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan nama berkas (+folder) dan mengembalikan pilihan',
      (tester) async {
    final result = <String?>[];
    await _open(tester, ['kebun/blok', 'kebun/jalan'], result);

    expect(find.text('blok'), findsOneWidget);
    expect(find.text('jalan'), findsOneWidget);
    expect(find.text('kebun'), findsNWidgets(2));

    await tester.tap(find.text('jalan'));
    await tester.pumpAndSettle();
    expect(result, ['kebun/jalan']);
  });

  testWidgets('Batal → null', (tester) async {
    final result = <String?>[];
    await _open(tester, ['a', 'b'], result);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a shapefile'), findsNothing);
    expect(result, [null]);
  });
}
