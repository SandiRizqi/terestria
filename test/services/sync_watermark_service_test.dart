import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final service = SyncWatermarkService();

  test('returns null when no watermark has been stored', () async {
    expect(await service.getLastPull('p1'), isNull);
  });

  test('round-trips a stored watermark at the same instant (UTC)', () async {
    final ts = DateTime.utc(2026, 6, 21, 10, 37, 1);
    await service.setLastPull('p1', ts);

    final got = await service.getLastPull('p1');
    expect(got, isNotNull);
    expect(got!.isUtc, isTrue);
    expect(got.isAtSameMomentAs(ts), isTrue);
  });

  test('normalises a local timestamp to the same UTC moment', () async {
    final local = DateTime(2026, 6, 21, 17, 37, 1); // local time
    await service.setLastPull('p1', local);

    final got = await service.getLastPull('p1');
    expect(got!.isAtSameMomentAs(local), isTrue);
  });

  test('keeps watermarks separate per project', () async {
    final a = DateTime.utc(2026, 1, 1);
    final b = DateTime.utc(2026, 2, 2);
    await service.setLastPull('p1', a);
    await service.setLastPull('p2', b);

    expect((await service.getLastPull('p1'))!.isAtSameMomentAs(a), isTrue);
    expect((await service.getLastPull('p2'))!.isAtSameMomentAs(b), isTrue);
  });

  test('clear removes the watermark, forcing a full pull next time', () async {
    await service.setLastPull('p1', DateTime.utc(2026, 6, 21));
    await service.clear('p1');
    expect(await service.getLastPull('p1'), isNull);
  });
}
