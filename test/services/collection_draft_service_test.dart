import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/collection_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

GeoPoint _p(double lon, double lat) =>
    GeoPoint(latitude: lat, longitude: lon, timestamp: DateTime.utc(2026, 9, 30));

void main() {
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
