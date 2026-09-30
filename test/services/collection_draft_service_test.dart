import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/services/collection_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

GeoPoint _p(double lon, double lat) =>
    GeoPoint(latitude: lat, longitude: lon, timestamp: DateTime.utc(2026, 9, 30));

void main() {
  _styleTests();

  test('listDrafts: hanya draft berisi, per project; rusak & kunci lain '
      'dilewati', () async {
    SharedPreferences.setMockInitialValues({
      'collection_draft_broken': '{bukan json',
      'collection_draft_wrongtype': 42,
      'app_settings': '{}',
    });
    final service = CollectionDraftService();
    await service.save('a', points: [_p(106.8, -6.2)], formData: const {});
    await service.save('b', points: const [], formData: const {'Name': 'x'});
    await service.save('c', points: const [], formData: const {}); // kosong

    final drafts = await service.listDrafts();

    expect(drafts.keys.toSet(), {'a', 'b'});
    expect(drafts['a']!.points.single.longitude, 106.8);
    expect(drafts['b']!.formData, {'Name': 'x'});
  });
}

// Draft ikut menyimpan style feature yang sedang dipilih (T3).
const _draftStyle = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 12,
);

void _styleTests() {
  test('draft menyimpan & memulihkan style; draft lama tanpa style → null',
      () async {
    SharedPreferences.setMockInitialValues({
      'collection_draft_lama':
          '{"points":[],"formData":{"Name":"x"},"savedAt":"2026-09-30T00:00:00Z"}',
    });
    final service = CollectionDraftService();
    await service.save('baru',
        points: [_p(106.8, -6.2)], formData: const {}, style: _draftStyle);

    expect((await service.load('baru'))!.style, _draftStyle);
    expect((await service.load('lama'))!.style, isNull);
  });

  test('style saja (tanpa titik & isian) tidak membuat draft', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CollectionDraftService();
    await service.save('a',
        points: const [], formData: const {}, style: _draftStyle);
    expect(await service.load('a'), isNull);
  });
}
