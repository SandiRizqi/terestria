import 'dart:convert';
import 'dart:typed_data';

import 'layer_importer.dart';

/// Pembaca atribut `.dbf` (dBase III/IV) sebuah shapefile.
///
/// Satu entri per record (urutan sama dengan `.shp`); record bertanda hapus
/// → null. Tipe: C (teks), N/F (angka; kosong → null), L (bool), D
/// (`YYYY-MM-DD`), lainnya teks. Encoding dari isi `.cpg` [cpg]; tanpa `.cpg`
/// dicoba UTF-8 lalu Latin-1 bila bukan UTF-8 valid.
List<Map<String, dynamic>?> readDbf(Uint8List bytes, {String? cpg}) {
  if (bytes.length < 33) {
    throw const LayerImportException('Berkas .dbf rusak (terlalu pendek)');
  }
  final bd = ByteData.sublistView(bytes);
  final count = bd.getUint32(4, Endian.little);
  final headerLen = bd.getUint16(8, Endian.little);
  final recordLen = bd.getUint16(10, Endian.little);
  final decode = _decoderFor(cpg);

  final fields = <_Field>[];
  var offset = 1; // byte flag hapus
  for (var p = 32; p + 32 <= headerLen && bytes[p] != 0x0D; p += 32) {
    final rawName = bytes.sublist(p, p + 11);
    final end = rawName.indexOf(0);
    final name = latin1.decode(end < 0 ? rawName : rawName.sublist(0, end)).trim();
    final f = _Field(name, String.fromCharCode(bytes[p + 11]), offset,
        bytes[p + 16], bytes[p + 17]);
    fields.add(f);
    offset += f.length;
  }
  if (fields.isEmpty || recordLen <= 0) {
    throw const LayerImportException('Berkas .dbf tidak berisi kolom');
  }

  final rows = <Map<String, dynamic>?>[];
  for (var i = 0; i < count; i++) {
    final start = headerLen + i * recordLen;
    if (start + recordLen > bytes.length) break; // terpotong: baca yang ada
    if (bytes[start] == 0x2A) {
      rows.add(null);
      continue;
    }
    final row = <String, dynamic>{};
    for (final f in fields) {
      final raw = bytes.sublist(start + f.offset, start + f.offset + f.length);
      row[f.name] = _value(f, decode(raw));
    }
    rows.add(row);
  }
  return rows;
}

class _Field {
  final String name;
  final String type;
  final int offset;
  final int length;
  final int decimals;
  const _Field(this.name, this.type, this.offset, this.length, this.decimals);
}

Object? _value(_Field f, String raw) {
  final s = raw.replaceAll('\u0000', '').trim();
  switch (f.type.toUpperCase()) {
    case 'N':
    case 'F':
      if (s.isEmpty || s.startsWith('*')) return null;
      if (f.decimals == 0) {
        final i = int.tryParse(s);
        if (i != null) return i;
      }
      final d = double.tryParse(s);
      return (d == null || d.isNaN || d.isInfinite) ? null : d;
    case 'L':
      if (s.isEmpty) return null;
      if ('TtYy'.contains(s[0])) return true;
      if ('FfNn'.contains(s[0])) return false;
      return null;
    case 'D':
      if (s.length != 8 || int.tryParse(s) == null) return null;
      return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
    default:
      return s;
  }
}

String Function(List<int>) _decoderFor(String? cpg) {
  final c = (cpg ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (c.isEmpty) return _utf8OrLatin1;
  if (c == 'UTF8' || c == '65001') return (b) => utf8.decode(b, allowMalformed: true);
  // Latin-1 / Windows-1252 / ANSI (umum di ekspor ArcGIS/QGIS Windows).
  return latin1.decode;
}

String _utf8OrLatin1(List<int> b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}
