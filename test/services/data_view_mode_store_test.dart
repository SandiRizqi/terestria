import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/data_view_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan tampilan data project (grid/list) disimpan di HP; bawaan grid.

void main() {
  test('belum pernah dipilih → grid', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await DataViewModeStore.load(), DataViewMode.grid);
  });

  test('pilihan disimpan dan dibaca kembali', () async {
    SharedPreferences.setMockInitialValues({});
    await DataViewModeStore.save(DataViewMode.list);
    expect(await DataViewModeStore.load(), DataViewMode.list);
    await DataViewModeStore.save(DataViewMode.grid);
    expect(await DataViewModeStore.load(), DataViewMode.grid);
  });

  test('nilai tersimpan tak dikenal → grid', () async {
    SharedPreferences.setMockInitialValues(
        {DataViewModeStore.prefsKey: 'mosaic'});
    expect(await DataViewModeStore.load(), DataViewMode.grid);
  });
}
