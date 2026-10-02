import '../models/form_field_model.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import '../utils/field_values.dart' show formatNumber, multiselectParts;

// Aturan project di HP (SPEC §3.6–3.7). Murni (tanpa Flutter). Rumus
// akurasi sama dengan server (gis-backend `validation.accuracy_violation`):
// titik manual (akurasi 0) dan titik tanpa akurasi tidak dinilai.

/// Fix GPS yang lebih tua dari ini dianggap tidak ada (sinyal hilang).
const Duration maxFixAge = Duration(seconds: 30);

/// Akurasi GPS titik (meter) bila > 0; null untuk titik manual / tanpa akurasi.
double? gpsAccuracy(GeoPoint point) {
  final a = point.accuracy;
  return a != null && a.isFinite && a > 0 ? a : null;
}

/// Rata-rata akurasi titik GPS; null bila tidak ada titik GPS.
double? averageGpsAccuracy(List<GeoPoint> points) {
  final values = [
    for (final p in points)
      if (gpsAccuracy(p) case final a?) a,
  ];
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

enum AccuracyMeasure { point, average }

/// Pelanggaran batas akurasi project.
class AccuracyViolation {
  final AccuracyMeasure measure;
  final double value;
  final double limit;
  const AccuracyViolation(this.measure, this.value, this.limit);
}

/// Pelanggaran batas akurasi record (sama dengan server), atau null bila
/// lolos: point = akurasi titiknya, line/polygon = rata-rata titik GPS.
/// Batas inklusif; tanpa batas / tanpa titik GPS → lolos.
AccuracyViolation? accuracyViolation(
    GeometryType type, List<GeoPoint> points, double? limit) {
  if (limit == null || limit <= 0 || points.isEmpty) return null;
  final measure =
      type == GeometryType.point ? AccuracyMeasure.point : AccuracyMeasure.average;
  final value = measure == AccuracyMeasure.point
      ? gpsAccuracy(points.first)
      : averageGpsAccuracy(points);
  if (value == null || value <= limit) return null;
  return AccuracyViolation(measure, value, limit);
}

/// 1 desimal; 2 desimal bila 1 desimal tampak tidak melebihi [limit].
String formatAccuracy(double value, {double? limit}) {
  var shown = double.parse(value.toStringAsFixed(1));
  if (limit != null && shown <= limit) {
    shown = double.parse(value.toStringAsFixed(2));
  }
  return formatNumber(shown);
}

/// Pesan pelanggaran (selaras dengan pesan server, tanpa "sync again").
String accuracyViolationText(AccuracyViolation v) {
  final value = formatAccuracy(v.value, limit: v.limit);
  final limit = formatNumber(v.limit);
  return v.measure == AccuracyMeasure.point
      ? "GPS accuracy $value m is above this project's limit ($limit m). "
          'Take the point again with a better GPS fix.'
      : "Average GPS accuracy $value m is above this project's limit ($limit m).";
}

/// Baris batas project di kartu status GPS layar koleksi.
String projectLimitText(double limit, double? currentAccuracy) {
  final text = 'Project limit ${formatNumber(limit)} m';
  if (currentAccuracy == null || currentAccuracy <= limit) return text;
  return '$text — current GPS ±${formatAccuracy(currentAccuracy, limit: limit)} m '
      'is not enough';
}

/// Hasil tombol "Add point".
sealed class PointCapture {
  const PointCapture();
}

/// Titik dari fix GPS (koordinat + akurasi + metadata fix).
class GpsPointCapture extends PointCapture {
  final GeoPoint point;
  const GpsPointCapture(this.point);
}

/// Titik manual di crosshair, disimpan dengan akurasi 0 (lolos aturan).
class ManualPointCapture extends PointCapture {
  const ManualPointCapture();
}

/// Titik ditolak (project point dengan batas akurasi).
class RejectedPointCapture extends PointCapture {
  final String message;
  const RejectedPointCapture(this.message);
}

/// Keputusan tombol "Add point" (SPEC §3.6):
/// - mode ikuti GPS + fix segar → titik GPS; untuk project point dengan
///   batas, fix di atas batas / tanpa fix / akurasi tak diketahui ditolak;
/// - tanpa mode ikuti (crosshair digeser manual) → titik manual.
PointCapture decidePointCapture({
  required bool followGps,
  required GeoPoint? fix,
  required GeometryType geometryType,
  required double? minAccuracy,
  required DateTime now,
}) {
  if (!followGps) return const ManualPointCapture();
  final fresh = fix != null && now.difference(fix.timestamp) <= maxFixAge;
  final limit = minAccuracy;
  final enforced =
      geometryType == GeometryType.point && limit != null && limit > 0;
  if (!enforced) {
    return fresh ? GpsPointCapture(fix) : const ManualPointCapture();
  }
  final needs = 'this project needs ${formatNumber(limit)} m or better.';
  if (!fresh) return RejectedPointCapture('No GPS fix yet — $needs');
  final accuracy = gpsAccuracy(fix);
  if (accuracy == null) {
    return RejectedPointCapture('GPS accuracy unknown — $needs');
  }
  if (accuracy > limit) {
    return RejectedPointCapture(
        'Accuracy ${formatAccuracy(accuracy, limit: limit)} m — $needs');
  }
  return GpsPointCapture(fix);
}

/// Ringkasan akurasi record dibanding batas project.
class AccuracySummaryInfo {
  final String text;
  final bool over;
  const AccuracySummaryInfo(this.text, this.over);
}

/// Ringkasan untuk form "Survey data", sheet Tracking Aktif, layar edit, dan
/// editor geometri, mis. "Average GPS accuracy 8.4 m — project limit 5 m".
/// Null bila project tanpa batas atau record tanpa titik GPS.
AccuracySummaryInfo? accuracySummary(
    GeometryType type, List<GeoPoint> points, double? limit) {
  if (limit == null || limit <= 0 || points.isEmpty) return null;
  final isPoint = type == GeometryType.point;
  final value = isPoint ? gpsAccuracy(points.first) : averageGpsAccuracy(points);
  if (value == null) return null;
  final over = value > limit;
  final label = isPoint ? 'GPS accuracy' : 'Average GPS accuracy';
  return AccuracySummaryInfo(
    '$label ${formatAccuracy(value, limit: over ? limit : null)} m — '
    'project limit ${formatNumber(limit)} m',
    over,
  );
}

/// Titik GPS yang akurasinya di atas batas (ditandai di editor geometri).
bool isAboveLimit(GeoPoint point, double? limit) =>
    limit != null && (gpsAccuracy(point) ?? 0) > limit;


// ─── Kombinasi unik (SPEC §3.7) ────────────────────────────────────────────
// Normalisasi HARUS sama dengan server (gis-backend `validation._key_parts`):
// - angka/desimal/skala: sebagai angka (10 = 10.0 = "10"; koma bukan desimal);
// - checkbox: true/false;
// - selain itu: trim, spasi berulang jadi satu, tanpa beda huruf besar/kecil.

final _whitespace = RegExp(r'\s+');

bool _isCheckedKey(Object value) {
  if (value == true) return true;
  final s = value.toString().trim().toLowerCase();
  return s == 'true' || s == '1';
}

/// Angka seperti Python `float(str.strip())` di server (koma tidak diterima).
double? _keyNumber(Object value) {
  if (value is bool) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

/// (nilai kunci, nilai tampilan) satu field, atau null bila kosong.
(String, String)? _keyPart(FieldType? type, Object? value) {
  if (value == null) return null;
  Object v = value;
  if (v is List) v = multiselectParts(v).join('; ');
  if (v is String && v.trim().isEmpty) return null;
  if (type == FieldType.checkbox) {
    final text = _isCheckedKey(v) ? 'true' : 'false';
    return (text, text);
  }
  if (type == FieldType.number ||
      type == FieldType.decimal ||
      type == FieldType.rating) {
    final n = _keyNumber(v);
    if (n != null && n.isFinite) {
      final text = formatNumber(n);
      return (text, text);
    }
  }
  final shown = v.toString().trim().replaceAll(_whitespace, ' ');
  return (shown.toLowerCase(), shown);
}

List<(String, (String, String))>? _uniqueKeyParts(
    Project project, Map<String, dynamic> formData) {
  if (project.uniqueFields.isEmpty) return null;
  final types = {for (final f in project.formFields) f.label: f.type};
  final parts = <(String, (String, String))>[];
  for (final label in project.uniqueFields) {
    final part = _keyPart(types[label], formData[label]);
    if (part == null) return null;
    parts.add((label, part));
  }
  return parts;
}

/// Nilai kunci kombinasi unik ternormalisasi (urut `uniqueFields`), atau
/// null bila project tanpa aturan atau ada field kunci yang kosong.
List<String>? uniqueKeyValues(Project project, Map<String, dynamic> formData) =>
    _uniqueKeyParts(project, formData)?.map((e) => e.$2.$1).toList();

bool _sameKey(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Record lokal lain di project dengan kunci yang sama, atau null.
GeoData? findDuplicate(
  Project project,
  Map<String, dynamic> formData,
  Iterable<GeoData> records, {
  String? excludeId,
}) {
  final key = uniqueKeyValues(project, formData);
  if (key == null) return null;
  for (final record in records) {
    if (record.id == excludeId || record.projectId != project.id) continue;
    final other = uniqueKeyValues(project, record.formData);
    if (other != null && _sameKey(key, other)) return record;
  }
  return null;
}

/// Pesan duplikat — sama dengan server (422 `duplicate`).
String duplicateMessage(Project project, Map<String, dynamic> formData) {
  final parts = _uniqueKeyParts(project, formData) ?? const [];
  final listed = parts.map((e) => '${e.$1}=${e.$2.$2}').join(', ');
  return '$listed already exists in this project.';
}

/// Edit mengubah kunci kombinasi unik? (Edit yang tidak mengubahnya tidak
/// dicek, jadi duplikat lama tetap bisa diedit.)
bool uniqueKeyChanged(Project project, Map<String, dynamic> before,
    Map<String, dynamic> after) {
  final a = uniqueKeyValues(project, before);
  final b = uniqueKeyValues(project, after);
  if (a == null || b == null) return a != b;
  return !_sameKey(a, b);
}
