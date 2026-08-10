import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/route_result.dart';

RouteInstruction _instr(String text) => RouteInstruction(
      text: text,
      distance: 100,
      time: 10000,
      sign: TurnSign.turnRight,
      interval: 0,
    );

void main() {
  group('RouteInstruction.streetName', () {
    test('extracts street after English connector', () {
      expect(_instr('Turn right onto Jl. Merdeka').streetName, 'Jl. Merdeka');
      expect(_instr('Continue on Main Street').streetName, 'Main Street');
    });

    test('extracts street after Indonesian connector', () {
      expect(
        _instr('Belok kanan ke Jalan Sudirman').streetName,
        'Jalan Sudirman',
      );
      expect(_instr('Lurus menuju Gg. Mawar').streetName, 'Gg. Mawar');
    });

    test('does not treat directions/destinations as street names', () {
      expect(_instr('Tiba di tujuan').streetName, '');
      expect(_instr('Belok kanan ke arah selatan').streetName, '');
      expect(_instr('Arrive at destination').streetName, '');
      expect(_instr('Keep left at roundabout').streetName, '');
      expect(_instr('Belok kiri di bundaran').streetName, '');
    });

    test('returns empty for bare maneuver text', () {
      expect(_instr('Continue').streetName, '');
      expect(_instr('Belok kiri').streetName, '');
      expect(_instr('').streetName, '');
    });

    test('surfaces non-generic text without connector as-is', () {
      expect(_instr('Jl. Ahmad Yani').streetName, 'Jl. Ahmad Yani');
    });
  });
}
