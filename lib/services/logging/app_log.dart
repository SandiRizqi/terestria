import 'dart:async';
import 'dart:io';

import 'log_redactor.dart';

enum LogLevel { debug, info, warn, error }

const _levelChar = {
  LogLevel.debug: 'D',
  LogLevel.info: 'I',
  LogLevel.warn: 'W',
  LogLevel.error: 'E',
};

String _two(int n) => n.toString().padLeft(2, '0');

/// `yyyyMMdd` (waktu lokal) — kunci nama berkas harian.
String logDayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}';

/// Satu baris log: `2026-09-29T08:00:01.123 I ENGINE  pesan`. Baris lanjutan
/// (stack trace) diberi indentasi agar tetap terbaca per entri.
String formatLogLine(DateTime t, LogLevel level, String tag, String message) {
  final ts = '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-'
      '${_two(t.day)}T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
  final body = message.replaceAll('\n', '\n    ');
  return '$ts ${_levelChar[level]} ${tag.padRight(7)} $body';
}

final _logFileName = RegExp(r'^([a-z]+)-(\d{8})\.log$');

/// Penulis berkas log ber-buffer untuk satu sumber (`app` = isolate UI,
/// `bg` = isolate background — tiap isolate punya berkas sendiri agar tak
/// saling menimpa). Berkas harian `<source>-yyyyMMdd.log`, diprune ke
/// [retention] & [maxBytes]. Tak pernah melempar: kegagalan I/O diabaikan.
class AppLogSink {
  AppLogSink({
    required this.dir,
    required this.source,
    DateTime Function()? now,
    this.maxBytes = 5 * 1024 * 1024,
    this.retention = const Duration(days: 7),
    this.flushInterval = const Duration(seconds: 2),
    Timer Function(Duration, void Function())? createTimer,
  })  : _now = now ?? DateTime.now,
        _createTimer = createTimer ?? ((d, cb) => Timer(d, cb));

  final Directory dir;
  final String source;
  final int maxBytes;
  final Duration retention;
  final Duration flushInterval;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _createTimer;

  final List<(String day, String line)> _buffer = [];
  Timer? _timer;
  Future<void> _chain = Future.value();
  String? _lastDay;

  /// Selesai saat semua flush yang sudah dijadwalkan rampung.
  Future<void> get idle => _chain;

  void write(LogLevel level, String tag, String message) {
    final t = _now();
    _buffer.add((
      logDayKey(t),
      formatLogLine(t, level, tag, LogRedactor.redact(message)),
    ));
    if (level == LogLevel.error) {
      flush(); // error jangan sampai hilang bila app mati sesaat kemudian
    } else {
      _timer ??= _createTimer(flushInterval, () {
        _timer = null;
        flush();
      });
    }
  }

  /// Tulis buffer ke berkas (berurutan, tak tumpang tindih).
  Future<void> flush() => _chain = _chain.then((_) => _writeBuffered());

  Future<void> _writeBuffered() async {
    if (_buffer.isEmpty) return;
    final entries = List.of(_buffer);
    _buffer.clear();
    final byDay = <String, StringBuffer>{};
    for (final (day, line) in entries) {
      (byDay[day] ??= StringBuffer()).writeln(line);
    }
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final e in byDay.entries) {
        await File('${dir.path}/$source-${e.key}.log')
            .writeAsString(e.value.toString(), mode: FileMode.append);
      }
      final today = byDay.keys.last;
      if (_lastDay != today) {
        _lastDay = today;
        await _pruneFiles();
      }
    } catch (_) {
      // Logger tak boleh menjatuhkan app.
    }
  }

  /// Hapus berkas log lebih tua dari [retention], lalu yang tertua sampai
  /// total ≤ [maxBytes]. Berkas hari ini milik sumber ini tak pernah dihapus.
  Future<void> prune() => _chain = _chain.then((_) => _pruneFiles());

  Future<void> _pruneFiles() async {
    try {
      if (!await dir.exists()) return;
      final now = _now();
      final cutoff =
          DateTime(now.year, now.month, now.day).subtract(retention);
      final protected = '$source-${logDayKey(now)}.log';

      final files = <(DateTime, String, File, int)>[];
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final m = _logFileName.firstMatch(name);
        if (m == null) continue;
        final d = m[2]!;
        final date = DateTime(int.parse(d.substring(0, 4)),
            int.parse(d.substring(4, 6)), int.parse(d.substring(6, 8)));
        if (date.isBefore(cutoff) && name != protected) {
          await e.delete();
          continue;
        }
        files.add((date, name, e, await e.length()));
      }

      files.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      var total = files.fold<int>(0, (s, f) => s + f.$4);
      for (final (_, name, file, size) in files) {
        if (total <= maxBytes) break;
        if (name == protected) continue;
        await file.delete();
        total -= size;
      }
    } catch (_) {
      // Abaikan: prune gagal tak boleh mengganggu logging.
    }
  }
}
