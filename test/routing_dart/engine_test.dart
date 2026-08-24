import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/route_result.dart';
import 'package:geoform_app/services/routing_dart/engine.dart';

void main() {
  const pbfPath = 'test/routing_dart/fixtures/tiny_roads.osm.pbf';

  test('initialize lalu calculateRoute → RouteResult valid', () async {
    final engine = DartRoutingEngine();
    expect(engine.isInitialized, isFalse);

    final ok = await engine.initialize(pbfPath);
    expect(ok, isTrue);
    expect(engine.isInitialized, isTrue);

    // node1(1.0,100.0) → node3(1.0,100.002); fixture way10 = [1,2,3]
    final r = await engine.calculateRoute(
      fromLat: 1.0,
      fromLon: 100.0,
      toLat: 1.0,
      toLon: 100.002,
      profile: 'car',
    );
    expect(r, isNotNull);
    expect(r!.points.length, greaterThanOrEqualTo(2));
    expect(r.distance, greaterThan(0));
    expect(r.time, greaterThan(0));
    expect(r.instructions, isNotEmpty);
    expect(r.instructions.last.sign, TurnSign.finish);
  });

  test('calculateRoute sebelum initialize → null', () async {
    final engine = DartRoutingEngine();
    final r = await engine.calculateRoute(
      fromLat: 1.0, fromLon: 100.0, toLat: 1.0, toLon: 100.002);
    expect(r, isNull);
  });

  test('initialize path tak ada → false, tak crash', () async {
    final engine = DartRoutingEngine();
    expect(await engine.initialize('test/routing_dart/fixtures/nope.pbf'),
        isFalse);
    expect(engine.isInitialized, isFalse);
  });

  test('initialize kedua kali di-skip (idempoten) kecuali forceRebuild', () async {
    final engine = DartRoutingEngine();
    expect(await engine.initialize(pbfPath), isTrue);
    expect(await engine.initialize(pbfPath), isTrue); // no-op, tetap true
    expect(engine.isInitialized, isTrue);
  });
}
