import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/logging/app_log.dart';
import 'package:geoform_app/services/logging/log_redactor.dart';

/// Timer palsu: tak berbunyi sendiri; test memanggil fire().
class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  bool cancelled = false;
  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

void main() {
  late Directory dir;
  late DateTime clock;
  late List<_FakeTimer> timers;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('applog_test');
    clock = DateTime(2026, 9, 29, 8, 0, 1, 123);
    timers = [];
  });
  tearDown(() => dir.delete(recursive: true));

  AppLogSink sink({String source = 'app', int maxBytes = 5 * 1024 * 1024}) =>
      AppLogSink(
        dir: dir,
        source: source,
        now: () => clock,
        maxBytes: maxBytes,
        createTimer: (_, cb) {
          final t = _FakeTimer(cb);
          timers.add(t);
          return t;
        },
      );

  String read(String name) => File('${dir.path}/$name').readAsStringSync();

  group('formatLogLine', () {
    test('timestamp ms, huruf level, tag rata kiri, pesan', () {
      expect(
        formatLogLine(DateTime(2026, 9, 29, 8, 0, 1, 123), LogLevel.info,
            'ENGINE', 'aktif'),
        '2026-09-29T08:00:01.123 I ENGINE  aktif',
      );
    });

    test('pesan multi-baris (stack trace) diberi indentasi', () {
      final line = formatLogLine(
          DateTime(2026, 9, 29), LogLevel.error, 'APP', 'gagal\n#0 main');
      expect(line, endsWith('gagal\n    #0 main'));
    });
  });

  group('LogRedactor', () {
    test('menyamarkan Authorization/Bearer', () {
      expect(LogRedactor.redact('Authorization: Bearer abc.def-123'),
          isNot(contains('abc.def-123')));
      expect(LogRedactor.redact('header Bearer eyJhbGciOi.x.y'),
          isNot(contains('eyJhbGciOi')));
    });

    test('menyamarkan password/token/api_key di pasangan kunci-nilai', () {
      final out = LogRedactor.redact(
          'login {"username":"budi","password":"rahasia1"} token=XYZ987 api_key: k-55');
      expect(out, contains('budi'));
      expect(out, isNot(contains('rahasia1')));
      expect(out, isNot(contains('XYZ987')));
      expect(out, isNot(contains('k-55')));
    });

    test('menyamarkan token FCM & JWT telanjang', () {
      final out = LogRedactor.redact(
          'fcm dGhpcy1pcy1hLWZha2U:APA91bHxYz_abcdefghijklmnop jwt eyJhbGc.eyJzdWIi.sig_1');
      expect(out, isNot(contains('APA91b')));
      expect(out, isNot(contains('eyJzdWIi')));
    });

    test('teks biasa & koordinat tak diubah', () {
      const s = 'fix -6.2000123,106.8166 ±4.2 m';
      expect(LogRedactor.redact(s), s);
    });
  });

  group('AppLogSink', () {
    test('info ditahan di buffer sampai timer flush berbunyi', () async {
      final s = sink();
      s.write(LogLevel.info, 'ENGINE', 'aktif');
      await s.idle;
      expect(File('${dir.path}/app-20260929.log').existsSync(), isFalse);

      timers.single.fire();
      await s.idle;
      expect(read('app-20260929.log'),
          '2026-09-29T08:00:01.123 I ENGINE  aktif\n');
    });

    test('error langsung di-flush (tak menunggu timer)', () async {
      final s = sink();
      s.write(LogLevel.info, 'ENGINE', 'aktif');
      s.write(LogLevel.error, 'SERVICE', 'mati sendiri');
      await s.idle;
      final text = read('app-20260929.log');
      expect(text, contains('I ENGINE  aktif'));
      expect(text, contains('E SERVICE mati sendiri'));
    });

    test('ganti hari → berkas baru; sumber bg terpisah', () async {
      final s = sink();
      s.write(LogLevel.error, 'A', 'hari 1');
      clock = DateTime(2026, 9, 30, 0, 0, 5);
      s.write(LogLevel.error, 'A', 'hari 2');
      final bg = sink(source: 'bg')..write(LogLevel.error, 'SERVICE', 'isolate');
      await s.idle;
      await bg.idle;
      expect(read('app-20260929.log'), contains('hari 1'));
      expect(read('app-20260930.log'), contains('hari 2'));
      expect(read('bg-20260930.log'), contains('isolate'));
    });

    test('rahasia disamarkan sebelum masuk berkas', () async {
      final s = sink();
      s.write(LogLevel.error, 'AUTH', 'Authorization: Bearer SECRET123');
      await s.idle;
      expect(read('app-20260929.log'), isNot(contains('SECRET123')));
    });

    test('prune: buang berkas > 7 hari & batasi total ukuran', () async {
      File('${dir.path}/app-20260901.log').writeAsStringSync('lama');
      File('${dir.path}/bg-20260924.log').writeAsStringSync('x' * 60);
      File('${dir.path}/app-20260925.log').writeAsStringSync('y' * 60);
      File('${dir.path}/app-20260929.log').writeAsStringSync('z' * 60);
      File('${dir.path}/catatan.txt').writeAsStringSync('bukan log');

      await sink(maxBytes: 130).prune();

      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, isNot(contains('app-20260901.log'))); // > 7 hari
      expect(names, isNot(contains('bg-20260924.log'))); // tertua, lewat batas
      expect(names, containsAll(['app-20260925.log', 'app-20260929.log']));
      expect(names, contains('catatan.txt')); // bukan berkas log
    });

    test('prune tak menghapus berkas hari ini milik sumber sendiri', () async {
      File('${dir.path}/app-20260929.log').writeAsStringSync('z' * 500);
      await sink(maxBytes: 100).prune();
      expect(File('${dir.path}/app-20260929.log').existsSync(), isTrue);
    });
  });
}
