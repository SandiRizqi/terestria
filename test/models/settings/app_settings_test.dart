import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/settings/app_settings.dart';

void main() {
  group('AppSettings.photoWatermark', () {
    test('default nonaktif (false)', () {
      expect(AppSettings.defaults().photoWatermark, isFalse);
      expect(AppSettings().photoWatermark, isFalse);
    });

    test('copyWith mengubah photoWatermark', () {
      final on = AppSettings().copyWith(photoWatermark: true);
      expect(on.photoWatermark, isTrue);
      // field lain tidak berubah
      expect(on.darkMode, isFalse);
      final off = on.copyWith(photoWatermark: false);
      expect(off.photoWatermark, isFalse);
    });

    test('toJson/fromJson round-trip mempertahankan nilai', () {
      final s = AppSettings().copyWith(photoWatermark: true);
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.photoWatermark, isTrue);
    });

    test('fromJson tanpa key (settings lama) → default false', () {
      // Simulasi JSON tersimpan sebelum fitur ini ada.
      final legacy = AppSettings.defaults().toJson()..remove('photoWatermark');
      expect(AppSettings.fromJson(legacy).photoWatermark, isFalse);
    });
  });
}
