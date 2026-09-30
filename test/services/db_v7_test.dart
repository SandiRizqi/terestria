import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/services/database_service.dart';

/// DB v7: kolom `geo_data.style` (JSON style per feature, null = default).

const _style = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 12,
);

GeoData _geo({LayerStyle? style}) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {'A': 1},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 9, 30, 1),
      style: style,
    );

void main() {
  test('versi DB naik ke 7', () {
    expect(DatabaseService.schemaVersion, 7);
  });

  test('migrasi v7 idempoten: kolom style hanya ditambah bila belum ada', () {
    final v6 = [
      {'cid': 0, 'name': 'id'},
      {'cid': 1, 'name': 'lastSyncError'},
    ];
    expect(DatabaseService.missingColumns(v6, const ['style']), ['style']);
    expect(
        DatabaseService.missingColumns(
            [...v6, {'cid': 2, 'name': 'STYLE'}], const ['style']),
        isEmpty);
  });

  group('baris DB geo_data', () {
    test('style disimpan sebagai JSON kontrak dan terbaca kembali utuh', () {
      final row = DatabaseService.geoDataToRow(_geo(style: _style));
      expect(row['style'], isA<String>());
      expect(row['style'], contains('"fillColor":"#FF9800"'));
      expect(DatabaseService.geoDataFromRow({...row}).style, _style);
    });

    test('tanpa style → kolom null → default', () {
      final row = DatabaseService.geoDataToRow(_geo());
      expect(row['style'], isNull);
      expect(DatabaseService.geoDataFromRow({...row}).style, isNull);
    });

    test('baris lama (sebelum v7, tanpa kolom style) tetap terbaca', () {
      final row = DatabaseService.geoDataToRow(_geo(style: _style))
        ..remove('style');
      expect(DatabaseService.geoDataFromRow(row).style, isNull);
    });

    test('isi kolom rusak tidak membuat record gagal dibaca', () {
      final row = {...DatabaseService.geoDataToRow(_geo()), 'style': '{rusak'};
      final back = DatabaseService.geoDataFromRow(row);
      expect(back.id, 'g1');
      expect(back.style, isNull);
    });
  });
}
