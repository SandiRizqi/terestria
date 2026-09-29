import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/geo_data_model.dart';

import '../utils/app_logger.dart';
/// Logs GPS points to a per-session CSV file, mirroring the APK's GpsLogger.
/// File name: gps_YYYYMMDD_HHmmss.csv in app documents directory.
/// Buffer 10 entries before each flush to minimise IO overhead.
class GpsLoggerService {
  static const int _bufferSize = 10;
  static const String _header = 'timestamp,latitude,longitude,speed_kmh,accuracy_m';

  final List<String> _buffer = [];
  File? _logFile;
  bool _isActive = false;

  bool get isActive => _isActive;
  String? get currentFilePath => _logFile?.path;

  /// Start a new logging session. Creates a new CSV file with a timestamp name.
  Future<void> startSession() async {
    if (_isActive) await stopSession();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final gpsDir = Directory('${dir.path}/gps_logs');
      if (!await gpsDir.exists()) await gpsDir.create(recursive: true);

      final now = DateTime.now();
      final name =
          'gps_${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}.csv';
      _logFile = File('${gpsDir.path}/$name');

      await _logFile!.writeAsString('$_header\n');
      _buffer.clear();
      _isActive = true;

      logDebug('📝 GpsLogger: session started → ${_logFile!.path}', tag: 'GPSLOG');
    } catch (e) {
      logError('❌ GpsLogger: failed to start session: $e', tag: 'GPSLOG');
    }
  }

  /// Log a single GPS point. Flushes to disk every [_bufferSize] points.
  Future<void> log(GeoPoint point) async {
    if (!_isActive || _logFile == null) return;

    final speedStr =
        point.speed != null ? point.speed!.toStringAsFixed(1) : '';
    final accStr =
        point.accuracy != null ? point.accuracy!.toStringAsFixed(1) : '';
    final row =
        '${point.timestamp.toIso8601String()},${point.latitude},${point.longitude},$speedStr,$accStr';

    _buffer.add(row);

    if (_buffer.length >= _bufferSize) {
      await _flush();
    }
  }

  /// Stop the session and flush any remaining buffered entries.
  Future<void> stopSession() async {
    if (!_isActive) return;

    await _flush();
    _isActive = false;
    logDebug('📝 GpsLogger: session stopped → ${_logFile?.path}', tag: 'GPSLOG');
    _logFile = null;
  }

  /// List all saved GPS log files, newest first.
  Future<List<File>> listLogFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final gpsDir = Directory('${dir.path}/gps_logs');
      if (!await gpsDir.exists()) return [];

      final files = await gpsDir
          .list()
          .where((e) => e is File && e.path.endsWith('.csv'))
          .map((e) => e as File)
          .toList();

      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (e) {
      logError('❌ GpsLogger: failed to list files: $e', tag: 'GPSLOG');
      return [];
    }
  }

  /// Delete log files older than [days] days.
  Future<void> deleteOldLogs({int days = 30}) async {
    try {
      final files = await listLogFiles();
      final cutoff = DateTime.now().subtract(Duration(days: days));

      for (final file in files) {
        final stat = await file.stat();
        if (stat.modified.isBefore(cutoff)) {
          await file.delete();
          logDebug('🗑️ GpsLogger: deleted old log ${file.path}', tag: 'GPSLOG');
        }
      }
    } catch (e) {
      logError('❌ GpsLogger: error deleting old logs: $e', tag: 'GPSLOG');
    }
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty || _logFile == null) return;
    try {
      final content = '${_buffer.join('\n')}\n';
      await _logFile!.writeAsString(content, mode: FileMode.append);
      _buffer.clear();
    } catch (e) {
      logError('❌ GpsLogger: flush error: $e', tag: 'GPSLOG');
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
