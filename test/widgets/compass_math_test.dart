import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/widgets/map/compass_button.dart';

void main() {
  test('normalizeDegrees → rentang (-180, 180]', () {
    expect(normalizeDegrees(0), 0);
    expect(normalizeDegrees(350), -10);     // shortest-arc: 350° = -10°
    expect(normalizeDegrees(370), 10);      // wrap > 360
    expect(normalizeDegrees(-10), -10);
    expect(normalizeDegrees(190), -170);
    expect(normalizeDegrees(-350), 10);
  });

  group('heading-up (peta menghadap arah hadap user)', () {
    test('rotasi peta = kebalikan heading, lewat jalur terpendek', () {
      expect(headingUpRotation(90, 0), -90); // hadap timur → peta diputar -90°
      expect(headingUpRotation(270, 0), 90);
      expect(headingUpRotation(10, 0), -10);
    });

    test('perubahan < 2° diabaikan (anti-jitter)', () {
      expect(headingUpRotation(91, -90), isNull);
      expect(headingUpRotation(93, -90), -93);
      // Melintasi ±180 tetap dianggap kecil.
      expect(headingUpRotation(181, 180), isNull);
    });

    test('putar manual > 5° dari rotasi otomatis → heading-up mati', () {
      expect(headingUpOverridden(-90, -93), isFalse);
      expect(headingUpOverridden(-90, -100), isTrue);
      expect(headingUpOverridden(178, -178), isFalse); // selisih 4° lewat ±180
    });
  });
}
