import 'dart:convert';
import 'dart:typed_data';

/// Pembuat shapefile kecil (.shp + .dbf) untuk test — cukup untuk menguji
/// pembaca tanpa menyimpan berkas biner di repo.

typedef Pt = List<double>;

/// Isi record Point (1) / PointZ (11) / PointM (21).
Uint8List pointRecord(double x, double y, {int type = 1}) {
  final b = BytesBuilder()
    ..add(_i32le(type))
    ..add(_f64le(x))
    ..add(_f64le(y));
  if (type == 11) b..add(_f64le(9))..add(_f64le(0));
  if (type == 21) b.add(_f64le(0));
  return b.toBytes();
}

/// Isi record MultiPoint (8/18/28).
Uint8List multiPointRecord(List<Pt> pts, {int type = 8}) {
  final b = BytesBuilder()
    ..add(_i32le(type))
    ..add(_bbox(pts))
    ..add(_i32le(pts.length));
  for (final p in pts) {
    b..add(_f64le(p[0]))..add(_f64le(p[1]));
  }
  _zmArrays(b, type, pts.length, zType: 18, mType: 28);
  return b.toBytes();
}

/// Isi record PolyLine (3/13/23) atau Polygon (5/15/25).
Uint8List partsRecord(List<List<Pt>> parts, {required int type}) {
  final pts = [for (final p in parts) ...p];
  final b = BytesBuilder()
    ..add(_i32le(type))
    ..add(_bbox(pts))
    ..add(_i32le(parts.length))
    ..add(_i32le(pts.length));
  var start = 0;
  for (final p in parts) {
    b.add(_i32le(start));
    start += p.length;
  }
  for (final p in pts) {
    b..add(_f64le(p[0]))..add(_f64le(p[1]));
  }
  final base = type % 10;
  _zmArrays(b, type, pts.length, zType: 10 + base, mType: 20 + base);
  return b.toBytes();
}

/// Record Null shape (0).
Uint8List nullRecord() => _i32le(0);

/// Berkas .shp lengkap dari isi record (header 100 byte + header record).
Uint8List buildShp(int shapeType, List<Uint8List> records) {
  final body = BytesBuilder();
  for (var i = 0; i < records.length; i++) {
    body
      ..add(_i32be(i + 1))
      ..add(_i32be(records[i].length ~/ 2))
      ..add(records[i]);
  }
  final bodyBytes = body.toBytes();
  final header = ByteData(100)
    ..setInt32(0, 9994, Endian.big)
    ..setInt32(24, (100 + bodyBytes.length) ~/ 2, Endian.big)
    ..setInt32(28, 1000, Endian.little)
    ..setInt32(32, shapeType, Endian.little);
  return Uint8List.fromList(
      [...header.buffer.asUint8List(), ...bodyBytes]);
}

class DbfField {
  final String name;
  final String type;
  final int length;
  final int decimals;
  const DbfField(this.name, this.type, this.length, [this.decimals = 0]);
}

/// Berkas .dbf dBase III. [records] = nilai teks per kolom; [deleted] = indeks
/// record bertanda hapus; [encode] = encoder teks (default UTF-8).
Uint8List buildDbf(
  List<DbfField> fields,
  List<List<String>> records, {
  Set<int> deleted = const {},
  List<int> Function(String) encode = _utf8,
}) {
  final headerLen = 32 + 32 * fields.length + 1;
  final recordLen = 1 + fields.fold<int>(0, (s, f) => s + f.length);
  final h = ByteData(32)
    ..setUint8(0, 3)
    ..setUint32(4, records.length, Endian.little)
    ..setUint16(8, headerLen, Endian.little)
    ..setUint16(10, recordLen, Endian.little);
  final b = BytesBuilder()..add(h.buffer.asUint8List());
  for (final f in fields) {
    final d = Uint8List(32);
    final name = ascii.encode(f.name);
    d.setRange(0, name.length, name);
    d[11] = f.type.codeUnitAt(0);
    d[16] = f.length;
    d[17] = f.decimals;
    b.add(d);
  }
  b.addByte(0x0D);
  for (var r = 0; r < records.length; r++) {
    b.addByte(deleted.contains(r) ? 0x2A : 0x20);
    for (var c = 0; c < fields.length; c++) {
      final cell = Uint8List(fields[c].length)..fillRange(0, fields[c].length, 0x20);
      final v = encode(records[r][c]);
      cell.setRange(0, v.length.clamp(0, cell.length), v);
      b.add(cell);
    }
  }
  b.addByte(0x1A);
  return b.toBytes();
}

List<int> _utf8(String s) => utf8.encode(s);

void _zmArrays(BytesBuilder b, int type, int n,
    {required int zType, required int mType}) {
  if (type == zType) {
    b.add(_f64le(0));
    b.add(_f64le(0));
    for (var i = 0; i < n; i++) {
      b.add(_f64le(5));
    }
  }
  if (type == zType || type == mType) {
    b.add(_f64le(0));
    b.add(_f64le(0));
    for (var i = 0; i < n; i++) {
      b.add(_f64le(0));
    }
  }
}

Uint8List _bbox(List<Pt> pts) {
  final xs = pts.map((p) => p[0]);
  final ys = pts.map((p) => p[1]);
  return Uint8List.fromList([
    ..._f64le(xs.reduce((a, b) => a < b ? a : b)),
    ..._f64le(ys.reduce((a, b) => a < b ? a : b)),
    ..._f64le(xs.reduce((a, b) => a > b ? a : b)),
    ..._f64le(ys.reduce((a, b) => a > b ? a : b)),
  ]);
}

Uint8List _i32le(int v) =>
    (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List();
Uint8List _i32be(int v) =>
    (ByteData(4)..setInt32(0, v, Endian.big)).buffer.asUint8List();
Uint8List _f64le(double v) =>
    (ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List();
