import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/tracking/tracking_engine.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';

Project _proj(String id) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Timer palsu: tak pernah berbunyi sendiri; test memanggil engine.tick().
class _FakeTimer implements Timer {
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

/// Port service palsu (tanpa plugin) — merekam start/stop/heartbeat.
class _FakeService {
  int starts = 0;
  int stops = 0;
  int heartbeats = 0;
  bool running = false;
  bool startResult = true;
  Completer<bool>? pendingStart;

  Future<bool> start() {
    starts++;
    if (pendingStart != null) return pendingStart!.future;
    running = startResult;
    return Future.value(startResult);
  }

  Future<void> stop() async {
    stops++;
    running = false;
  }
}

void main() {
  late TrackingSessionManager mgr;
  late _FakeService svc;
  late List<_FakeTimer> timers;
  late DateTime clock;
  late TrackingEngine engine;

  setUp(() {
    mgr = TrackingSessionManager(maxConcurrent: 3);
    svc = _FakeService();
    timers = [];
    clock = DateTime(2026, 1, 1, 8);
    engine = TrackingEngine(
      manager: mgr,
      startService: svc.start,
      stopService: svc.stop,
      sendHeartbeat: () => svc.heartbeats++,
      isServiceRunning: () => svc.running,
      periodicTimer: (_, __) {
        final t = _FakeTimer();
        timers.add(t);
        return t;
      },
      now: () => clock,
    )..attach();
  });

  tearDown(() => engine.detach());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('sesi pertama menyalakan service + heartbeat app-level', () async {
    mgr.start(_proj('a'));
    await settle();
    expect(svc.starts, 1);
    expect(engine.isActive, isTrue);
    expect(timers.single.isActive, isTrue);
  });

  test('heartbeat tetap terkirim tanpa layar collection (bug C1)', () async {
    mgr.start(_proj('a'));
    await settle();
    final before = svc.heartbeats; // 1 heartbeat langsung saat aktif
    // Tak ada DataCollectionScreen: hanya engine yang berdetak.
    for (var i = 0; i < 6; i++) {
      engine.tick();
    }
    expect(svc.heartbeats - before, 6);
  });

  test('sesi kedua tak menyalakan ulang; stop satu sesi tak mematikan service',
      () async {
    mgr.start(_proj('a'));
    await settle();
    mgr.start(_proj('b'));
    await settle();
    expect(svc.starts, 1);

    mgr.stop('a');
    await settle();
    expect(svc.stops, 0);
    expect(engine.isActive, isTrue);

    mgr.stop('b');
    await settle();
    expect(svc.stops, 1);
    expect(engine.isActive, isFalse);
    expect(timers.single.cancelled, isTrue);

    final before = svc.heartbeats;
    engine.tick(); // setelah berhenti → tak ada heartbeat lagi
    expect(svc.heartbeats, before);
  });

  test('semua sesi di-pause → service berhenti; resume → menyala lagi',
      () async {
    mgr.start(_proj('a'));
    await settle();
    mgr.pause('a');
    await settle();
    expect(svc.stops, 1);
    expect(engine.isActive, isFalse);

    mgr.resume('a');
    await settle();
    expect(svc.starts, 2);
    expect(engine.isActive, isTrue);
  });

  test('draft pendingSave tidak menahan service', () async {
    mgr.start(_proj('a'));
    mgr.start(_proj('b'));
    await settle();
    mgr.finish('a'); // A menunggu disimpan
    mgr.finish('b');
    await settle();
    expect(svc.stops, 1);
    expect(engine.isActive, isFalse);
  });

  test('ensureRunning: panggilan bersamaan berbagi satu start', () async {
    svc.pendingStart = Completer<bool>();
    mgr.start(_proj('a')); // memicu start (belum selesai)
    final f1 = engine.ensureRunning();
    final f2 = engine.ensureRunning();
    expect(svc.starts, 1);
    svc.running = true;
    svc.pendingStart!.complete(true);
    expect(await f1, isTrue);
    expect(await f2, isTrue);
  });

  test('ensureRunning: service sudah jalan → tak start ulang', () async {
    mgr.start(_proj('a'));
    await settle();
    expect(await engine.ensureRunning(), isTrue);
    expect(svc.starts, 1);
  });

  test('ensureRunning mengembalikan false bila service gagal start', () async {
    svc.startResult = false;
    mgr.start(_proj('a'));
    expect(await engine.ensureRunning(), isFalse);
  });

  test('self-heal: service mati sendiri saat sesi merekam → dinyalakan ulang '
      '(dengan backoff)', () async {
    mgr.start(_proj('a'));
    await settle();
    expect(svc.starts, 1);

    svc.running = false; // isolate berhenti sendiri (dilaporkan T1)
    engine.tick();
    await settle();
    expect(svc.starts, 2);

    svc.running = false; // mati lagi, tapi masih dalam jendela backoff
    clock = clock.add(const Duration(seconds: 5));
    engine.tick();
    await settle();
    expect(svc.starts, 2);

    clock = clock.add(const Duration(seconds: 30));
    engine.tick();
    await settle();
    expect(svc.starts, 3);
  });
}
