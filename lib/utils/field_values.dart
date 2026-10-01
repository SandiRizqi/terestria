import '../models/form_field_model.dart';

/// Nilai isian per tipe field (SPEC §3.1/§3.3): format & parse, validasi, dan
/// teks tampilan. Murni (tanpa Flutter). Aturan validasinya sama dengan
/// server (`validate_form_data`) dan web (`fieldTypes.ts`); di HP pelanggaran
/// memblokir simpan.

/// Pemisah opsi pada nilai pilihan ganda: "A; B".
const String multiselectSeparator = ';';

/// Angka dengan koma atau titik desimal ("2,5" / "2.5"); null bila bukan angka.
double? parseLocaleNumber(String input) {
  final s = input.trim().replaceAll(',', '.');
  if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
  return double.tryParse(s);
}

/// Angka dari nilai tersimpan (num atau teks angka); bool bukan angka.
double? numberValue(Object? value) {
  if (value is bool || value == null) return null;
  if (value is num) return value.toDouble();
  return parseLocaleNumber(value.toString());
}

/// Skala 1–5 sebagai int (angka/teks angka bulat); null bila bukan bulat.
int? ratingValue(Object? value) {
  final n = numberValue(value);
  if (n == null || n != n.roundToDouble()) return null;
  return n.toInt();
}

/// Opsi terpilih dari nilai pilihan ganda; bagian kosong dibuang.
List<String> multiselectParts(Object? value) {
  if (value == null) return const [];
  final parts = value is List
      ? value.map((e) => e.toString())
      : value.toString().split(multiselectSeparator);
  return [
    for (final p in parts)
      if (p.trim().isNotEmpty) p.trim(),
  ];
}

/// Nilai pilihan ganda dari opsi terpilih, urut sesuai [options]; nilai yang
/// tidak ada di daftar (mis. opsi lama) tetap disimpan di akhir.
String joinMultiselect(Iterable<String> selected, List<String>? options) {
  final chosen = selected.toSet();
  final list = options ?? const <String>[];
  return [
    for (final o in list)
      if (chosen.contains(o)) o,
    for (final s in chosen)
      if (!list.contains(s)) s,
  ].join('$multiselectSeparator ');
}

final _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$');

/// Jam dari `HH:mm` / `HH:mm:ss`; null bila tidak valid.
({int hour, int minute})? parseTimeValue(Object? value) {
  if (value is! String) return null;
  final m = _time.firstMatch(value.trim());
  if (m == null) return null;
  return (hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Nilai tersimpan field waktu: `HH:mm`.
String formatTimeValue(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

final _dateTime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-]\d{2}:?\d{2})?$');

/// Tanggal + jam dari nilai tersimpan (ISO); null bila tidak valid atau tanpa
/// jam. Detik diabaikan (format tersimpan selalu `:00`).
DateTime? parseDateTimeValue(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  final m = _dateTime.firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!), h = int.parse(m.group(4)!);
  final mi = int.parse(m.group(5)!), sec = int.parse(m.group(6) ?? '0');
  final daysInMonth = mo >= 1 && mo <= 12 ? DateTime(y, mo + 1, 0).day : 0;
  if (d < 1 || d > daysInMonth || h > 23 || mi > 59 || sec > 59) return null;
  if (m.group(7) != null) {
    final local = DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toLocal();
    return local == null
        ? null
        : DateTime(local.year, local.month, local.day, local.hour, local.minute);
  }
  return DateTime(y, mo, d, h, mi);
}

/// Nilai tersimpan field tanggal-waktu: `YYYY-MM-DDTHH:mm:00.000` (lokal).
String formatDateTimeValue(DateTime value) =>
    DateTime(value.year, value.month, value.day, value.hour, value.minute)
        .toIso8601String();

/// Angka tanpa `.0` bila bulat: `200`, `35.5`.
String formatNumber(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

bool _isBlank(Object? v) =>
    v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

bool _isChecked(Object? v) =>
    v == true || v?.toString().toLowerCase() == 'true' || v?.toString() == '1';

String? _rangeIssue(FormFieldModel field, double n) {
  final unit = (field.unit ?? '').trim();
  final suffix = unit.isEmpty ? '' : ' $unit';
  final low = field.min, high = field.max;
  if (low != null && high != null) {
    return n < low || n > high
        ? 'must be between ${formatNumber(low)} and ${formatNumber(high)}$suffix'
        : null;
  }
  if (low != null && n < low) return 'must be at least ${formatNumber(low)}$suffix';
  if (high != null && n > high) return 'must be at most ${formatNumber(high)}$suffix';
  return null;
}

/// Masalah isian satu field (mis. "is required"), atau null bila valid.
String? fieldValueIssue(FormFieldModel field, Object? value) {
  switch (field.type) {
    case FieldType.photo:
      final count = value is List ? value.length : (_isBlank(value) ? 0 : 1);
      final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
      final maxPhotos = field.maxPhotos ?? 1;
      if (count < minPhotos) {
        return minPhotos == 1 ? 'needs a photo' : 'needs at least $minPhotos photos';
      }
      return count > maxPhotos ? 'allows at most $maxPhotos photo(s)' : null;
    case FieldType.checkbox:
      return field.required && !_isChecked(value) ? 'must be checked' : null;
    default:
      break;
  }

  final empty = _isBlank(value) ||
      (field.type == FieldType.multiselect && multiselectParts(value).isEmpty);
  if (empty) return field.required ? 'is required' : null;

  switch (field.type) {
    case FieldType.number:
    case FieldType.decimal:
      final n = numberValue(value);
      return n == null ? 'is not a valid number' : _rangeIssue(field, n);
    case FieldType.time:
      return parseTimeValue(value) == null ? 'is not a valid time' : null;
    case FieldType.datetime:
      return parseDateTimeValue(value) == null ? 'is not a valid date and time' : null;
    case FieldType.multiselect:
      final options = field.options ?? const <String>[];
      final unknown = [
        for (final p in multiselectParts(value))
          if (!options.contains(p)) p,
      ];
      if (unknown.isEmpty) return null;
      return unknown.length == 1
          ? 'has an option that is not in the list: ${unknown.single}'
          : 'has options that are not in the list: ${unknown.join(', ')}';
    case FieldType.rating:
      final r = ratingValue(value);
      return r == null || r < 1 || r > 5 ? 'must be 1–5' : null;
    case FieldType.text:
    case FieldType.textarea:
    case FieldType.date:
    case FieldType.dropdown:
    case FieldType.photo:
    case FieldType.checkbox:
      return null;
  }
}

/// Teks tampilan nilai: Yes/No, `4 / 5`, `35.5 cm`, `2026-10-01 07:15`, dst.
/// Nilai yang tidak sesuai format tipenya ditampilkan apa adanya.
String displayFieldValue(FormFieldModel field, Object? value) {
  if (value == null) return '';
  switch (field.type) {
    case FieldType.checkbox:
      return _isChecked(value) ? 'Yes' : 'No';
    case FieldType.rating:
      final r = ratingValue(value);
      return r == null ? value.toString() : '$r / 5';
    case FieldType.number:
    case FieldType.decimal:
      final n = numberValue(value);
      if (n == null) return value.toString();
      final unit = (field.unit ?? '').trim();
      return unit.isEmpty ? formatNumber(n) : '${formatNumber(n)} $unit';
    case FieldType.datetime:
      final dt = parseDateTimeValue(value);
      return dt == null
          ? value.toString()
          : '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
              '${_two(dt.hour)}:${_two(dt.minute)}';
    case FieldType.date:
      final s = value.toString();
      return RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(s)?.group(0) ?? s;
    case FieldType.multiselect:
      return multiselectParts(value).join('$multiselectSeparator ');
    case FieldType.photo:
      final n = value is List ? value.length : (_isBlank(value) ? 0 : 1);
      return '$n photo(s)';
    case FieldType.text:
    case FieldType.textarea:
    case FieldType.time:
    case FieldType.dropdown:
      return value.toString();
  }
}
