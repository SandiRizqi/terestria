import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/screens/project/widgets/pull_filter_sheet.dart';

Future<void> _pump(WidgetTester tester, void Function(Map<String, String>) onSubmit,
    {List<String> keys = const ['AFD_NAME', 'WERKS']}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PullFilterSheet(fieldKeys: keys, onSubmit: onSubmit),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('submitting one key=value calls onSubmit with that pair',
      (tester) async {
    Map<String, String>? captured;
    await _pump(tester, (f) => captured = f);

    // Pilih key pada baris pertama.
    await tester.tap(find.byKey(const ValueKey('filter-key-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AFD_NAME').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('filter-value-0')), 'E32');
    await tester.tap(find.byKey(const ValueKey('pull-filter-submit')));
    await tester.pumpAndSettle();

    expect(captured, {'AFD_NAME': 'E32'});
  });

  testWidgets('add a second row → two filters submitted (AND)', (tester) async {
    Map<String, String>? captured;
    await _pump(tester, (f) => captured = f);

    await tester.tap(find.byKey(const ValueKey('filter-key-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AFD_NAME').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-value-0')), 'E32');

    await tester.tap(find.byKey(const ValueKey('pull-filter-add-row')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('filter-key-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WERKS').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-value-1')), '5421');

    await tester.tap(find.byKey(const ValueKey('pull-filter-submit')));
    await tester.pumpAndSettle();

    expect(captured, {'AFD_NAME': 'E32', 'WERKS': '5421'});
  });

  testWidgets('empty filters allowed → onSubmit with empty map', (tester) async {
    Map<String, String>? captured;
    await _pump(tester, (f) => captured = f);

    await tester.tap(find.byKey(const ValueKey('pull-filter-submit')));
    await tester.pumpAndSettle();

    expect(captured, isEmpty);
  });

  testWidgets('rows with no chosen key or blank value are ignored',
      (tester) async {
    Map<String, String>? captured;
    await _pump(tester, (f) => captured = f);

    // Key dipilih tapi value kosong → diabaikan.
    await tester.tap(find.byKey(const ValueKey('filter-key-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AFD_NAME').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pull-filter-submit')));
    await tester.pumpAndSettle();

    expect(captured, isEmpty);
  });
}
