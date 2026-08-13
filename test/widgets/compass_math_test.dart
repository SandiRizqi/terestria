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
}
