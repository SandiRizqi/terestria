import 'package:shared_preferences/shared_preferences.dart';

/// Cara menampilkan data project: grid (bawaan) atau list.
enum DataViewMode { grid, list }

/// Pilihan tampilan data project, disimpan di HP dan berlaku untuk semua
/// project.
class DataViewModeStore {
  static const prefsKey = 'project_data_view_mode';

  static Future<DataViewMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(prefsKey);
    return DataViewMode.values.where((m) => m.name == name).firstOrNull ??
        DataViewMode.grid;
  }

  static Future<void> save(DataViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.name);
  }
}
