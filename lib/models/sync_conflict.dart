import 'geo_data_model.dart';

/// Record yang BERKONFLIK: diedit di HP, dan sejak versi yang terakhir dilihat
/// app juga diubah di server (server menolak push dengan 409, atau pull
/// menemukannya). Versi server disimpan sampai user memilih "Keep mine" atau
/// "Use server version" — tak ada editan yang hilang diam-diam.
class SyncConflict {
  final String geoDataId;
  final String projectId;

  /// Versi server dalam format JSON server/mobile (`GeoData.fromJson`).
  final Map<String, dynamic> serverJson;
  final DateTime detectedAt;

  const SyncConflict({
    required this.geoDataId,
    required this.projectId,
    required this.serverJson,
    required this.detectedAt,
  });

  /// Versi server sebagai [GeoData]; null bila JSON-nya tak terbaca.
  GeoData? get serverVersion {
    try {
      return GeoData.fromJson(serverJson);
    } catch (_) {
      return null;
    }
  }
}
