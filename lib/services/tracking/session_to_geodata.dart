import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';

/// Hasil validasi geometri sebuah sesi terhadap tipe project.
class GeometryValidation {
  final bool ok;
  final String? error;
  const GeometryValidation(this.ok, [this.error]);
}

/// Cukupkah [pointCount] untuk membentuk geometri [type]?
/// line ≥2, polygon ≥3, point ≥1.
GeometryValidation validateGeometry(GeometryType type, int pointCount) {
  switch (type) {
    case GeometryType.line:
      return pointCount >= 2
          ? const GeometryValidation(true)
          : const GeometryValidation(false, 'Line requires at least 2 points');
    case GeometryType.polygon:
      return pointCount >= 3
          ? const GeometryValidation(true)
          : const GeometryValidation(
              false, 'Polygon requires at least 3 points');
    case GeometryType.point:
      return pointCount >= 1
          ? const GeometryValidation(true)
          : const GeometryValidation(false, 'Point requires at least 1 point');
  }
}

/// Bangun [GeoData] dari sesi tracking sebuah project. Murni (id & waktu
/// disuntik dari pemanggil) agar mudah diuji. Validasi geometri lewat
/// [validateGeometry] dilakukan pemanggil sebelum menyimpan. [style] null =
/// ikut default Settings.
GeoData buildGeoData({
  required String id,
  required Project project,
  required List<GeoPoint> points,
  required Map<String, dynamic> formData,
  String? collectedBy,
  DateTime? now,
  LayerStyle? style,
}) {
  final ts = now ?? DateTime.now();
  return GeoData(
    id: id,
    projectId: project.id,
    formData: formData,
    points: points,
    createdAt: ts,
    updatedAt: ts,
    collectedBy: collectedBy,
    style: style,
  );
}
