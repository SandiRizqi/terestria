import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'layer_importer.dart';
import 'prj_projection.dart';
import 'shapefile_reader.dart';
import 'zip_helpers.dart';

/// Zip berisi lebih dari satu shapefile — UI meminta user memilih salah satu
/// ([names]) lalu mengimpor ulang dengan `shapefileName`.
class MultipleShapefilesException extends LayerImportException {
  final List<String> names;
  const MultipleShapefilesException(this.names)
      : super('The zip contains several shapefiles — choose one');
}

/// Nama (path tanpa `.shp`) semua shapefile dalam zip, urut abjad. Berkas
/// metadata macOS (`__MACOSX/`, `._*`) diabaikan.
List<String> listZipShapefiles(List<ArchiveFile> files) {
  final names = <String>{};
  for (final f in files) {
    final lower = f.name.toLowerCase();
    if (!lower.endsWith('.shp') || _isJunk(f.name)) continue;
    names.add(f.name.substring(0, f.name.length - 4));
  }
  return names.toList()..sort();
}

/// Shapefile ber-zip → GeoJSON (koordinat WGS84 lon/lat).
///
/// Wajib ada `.shp` + `.dbf` dengan nama sama; `.prj` menentukan proyeksi
/// (lihat [transformFromPrj]); `.cpg` menentukan encoding atribut.
Map<String, dynamic> zippedShapefileToGeoJson(Uint8List zip,
    {String? shapefileName}) {
  final files = decodeZipOrThrow(zip, 'The .zip file');
  final names = listZipShapefiles(files);
  if (names.isEmpty) {
    throw const LayerImportException(
        'The zip has no shapefile (.shp). For zipped KML use .kmz');
  }
  final String base;
  if (shapefileName != null) {
    if (!names.contains(shapefileName)) {
      throw LayerImportException('Shapefile "$shapefileName" is not in the zip');
    }
    base = shapefileName;
  } else if (names.length > 1) {
    throw MultipleShapefilesException(names);
  } else {
    base = names.single;
  }

  ArchiveFile? part(String ext) {
    final want = '$base.$ext'.toLowerCase();
    for (final f in files) {
      if (f.name.toLowerCase() == want) return f;
    }
    return null;
  }

  final shp = part('shp')!;
  final dbf = part('dbf');
  if (dbf == null) {
    throw LayerImportException(
        'Shapefile "${_short(base)}" is incomplete: the .dbf file is missing '
        'from the zip (.shp + .dbf are required, .shx + .prj recommended)');
  }
  final prj = part('prj');
  final cpg = part('cpg');

  final shpBytes = shp.content;
  final transform = transformFromPrj(
    prj == null ? null : latin1.decode(prj.content),
    bbox: _shpBbox(shpBytes),
  );
  final fc = shapefileToGeoJson(
    shp: shpBytes,
    dbf: dbf.content,
    cpg: cpg == null ? null : latin1.decode(cpg.content),
    transform: transform,
  );
  _checkLonLat(fc);
  return fc;
}

bool _isJunk(String name) =>
    name.startsWith('__MACOSX/') || name.split('/').last.startsWith('._');

String _short(String base) => base.split('/').last;

List<double> _shpBbox(Uint8List shp) {
  if (shp.length < 68) return const [];
  final bd = ByteData.sublistView(shp);
  return [for (var o = 36; o < 68; o += 8) bd.getFloat64(o, Endian.little)];
}

/// Pengaman terakhir: hasil harus lon/lat valid — mencegah data proyeksi
/// lain tampil di posisi salah tanpa peringatan.
void _checkLonLat(Map<String, dynamic> fc) {
  void walk(Object? c) {
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      final lon = (c[0] as num).toDouble(), lat = (c[1] as num).toDouble();
      if (!lon.isFinite || !lat.isFinite || lon.abs() > 180 || lat.abs() > 90) {
        throw const LayerImportException(
            'Shapefile coordinates are outside the lon/lat range — check the .prj file');
      }
      return;
    }
    if (c is List) c.forEach(walk);
  }

  for (final f in fc['features'] as List) {
    walk(((f as Map)['geometry'] as Map)['coordinates']);
  }
}
