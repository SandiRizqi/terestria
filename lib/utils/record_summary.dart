import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import '../models/settings/app_settings.dart';
import '../widgets/map/tools/measure_math.dart';
import 'record_title.dart';

/// Ringkasan satu record untuk baris tampilan list data project (template
/// "Project detail · data"): `<isian kedua> · <luas/panjang> · <pengumpul>, <waktu>`.
/// Judul baris tetap [recordTitle].

const _maxValueLength = 30;

/// Waktu singkat: jam bila hari ini, "yesterday", tanggal + bulan pada tahun
/// yang sama, selain itu tanggal lengkap.
String shortRecordTime(DateTime time, DateTime now) {
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return DateFormat('HH:mm').format(time);
  if (daysAgo == 1) return 'yesterday';
  if (time.year == now.year) return DateFormat('d MMM').format(time);
  return DateFormat('d MMM yyyy').format(time);
}

/// Pengumpul record: "you" bila sama dengan user yang login (abaikan huruf
/// besar/kecil & spasi di tepi), selain itu namanya; null bila tidak ada.
String? collectorLabel(String? collectedBy, String? currentUsername) {
  final who = collectedBy?.trim();
  if (who == null || who.isEmpty) return null;
  final me = currentUsername?.trim().toLowerCase();
  return who.toLowerCase() == me ? 'you' : who;
}

/// Luas polygon / panjang line dengan unit dari [settings]; null untuk point
/// atau geometri yang titiknya belum cukup.
String? recordMeasureText(
    GeoData data, GeometryType type, AppSettings settings) {
  final points =
      data.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  switch (type) {
    case GeometryType.point:
      return null;
    case GeometryType.line:
      if (points.length < 2) return null;
      return settings.formatDistance(polylineLengthMeters(points));
    case GeometryType.polygon:
      if (points.length < 3) return null;
      return settings.formatArea(polygonAreaSqMeters(points));
  }
}

/// Baris kedua tampilan list. Isian kedua = nilai non-foto berikutnya setelah
/// isian yang dipakai judul, terformat sesuai tipe field (kosong dilewati,
/// dipotong 30 karakter).
String recordSubtitle(
  GeoData data,
  Project project, {
  required String? currentUsername,
  required DateTime now,
  required AppSettings settings,
}) {
  final values = data.formData.entries
      .where((e) => !isPhotoFieldName(e.key, project))
      .map((e) => recordValueText(e.key, e.value, project).trim())
      .toList();
  // Isian pertama sudah menjadi judul; isian kedua yang terisi jadi ringkasan.
  final second = values.skip(1).where((v) => v.isNotEmpty).firstOrNull;

  final who = collectorLabel(data.collectedBy, currentUsername);
  final when = shortRecordTime(data.createdAt, now);
  return [
    if (second != null)
      second.length > _maxValueLength
          ? '${second.substring(0, _maxValueLength)}…'
          : second,
    if (recordMeasureText(data, project.geometryType, settings) case final m?) m,
    who == null ? when : '$who, $when',
  ].join(' · ');
}
