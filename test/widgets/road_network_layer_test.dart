import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/widgets/map/road_network_layer.dart';

/// Keputusan tampil layer jalan: hanya bila toggle ON + ada data + zoom > 10.
void main() {
  group('roadLayerVisible', () {
    test('semua syarat terpenuhi (zoom > 10) → tampil', () {
      expect(roadLayerVisible(visible: true, hasData: true, zoom: 11), isTrue);
      expect(roadLayerVisible(visible: true, hasData: true, zoom: 16), isTrue);
    });

    test('zoom <= 10 → sembunyi (zoom-gate)', () {
      expect(roadLayerVisible(visible: true, hasData: true, zoom: 10), isFalse);
      expect(roadLayerVisible(visible: true, hasData: true, zoom: 8), isFalse);
    });

    test('toggle mati → sembunyi walau zoom & data ok', () {
      expect(roadLayerVisible(visible: false, hasData: true, zoom: 15), isFalse);
    });

    test('tidak ada data → sembunyi (guard)', () {
      expect(roadLayerVisible(visible: true, hasData: false, zoom: 15), isFalse);
    });

    test('minZoom bisa disetel', () {
      expect(
          roadLayerVisible(
              visible: true, hasData: true, zoom: 13, minZoom: 12),
          isTrue);
      expect(
          roadLayerVisible(
              visible: true, hasData: true, zoom: 12, minZoom: 12),
          isFalse);
    });
  });
}
