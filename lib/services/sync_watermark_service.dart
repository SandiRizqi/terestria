import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan watermark "terakhir tarik" per project untuk delta sync.
///
/// Watermark = nilai `updatedAt` (server) tertinggi yang sudah berhasil
/// ditarik untuk sebuah project. Pada pull berikutnya klien mengirim
/// `updated_after=<watermark>` sehingga server hanya mengembalikan record yang
/// berubah. Disimpan sebagai ISO8601 UTC agar bebas dari zona waktu device.
class SyncWatermarkService {
  static final SyncWatermarkService _instance =
      SyncWatermarkService._internal();
  factory SyncWatermarkService() => _instance;
  SyncWatermarkService._internal();

  static String _key(String projectId) => 'last_pull_$projectId';

  /// Watermark (UTC) untuk [projectId], atau null bila belum pernah tersimpan
  /// (artinya pull berikutnya harus full pull).
  Future<DateTime?> getLastPull(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_key(projectId));
    if (iso == null) return null;
    return DateTime.tryParse(iso)?.toUtc();
  }

  /// Simpan watermark untuk [projectId]. Dinormalisasi ke UTC sebelum disimpan.
  Future<void> setLastPull(String projectId, DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(projectId),
      timestamp.toUtc().toIso8601String(),
    );
  }

  /// Hapus watermark [projectId] → memaksa full pull pada sinkron berikutnya.
  Future<void> clear(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(projectId));
  }
}
