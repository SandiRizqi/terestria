import '../../models/geo_data_model.dart';
import 'tracking_session.dart';

/// Agregator ringkasan GPS per [interval] untuk berkas log — pengganti log per
/// fix (yang membanjiri berkas). Contoh baris:
/// `1 mnt · HP 58 fix (3 ditolak, median ±4.2 m) · "Jalan A" +55 (total 420)`.
class TrackingLogSummary {
  TrackingLogSummary({
    required DateTime start,
    this.interval = const Duration(minutes: 1),
  }) : _windowStart = start;

  final Duration interval;
  DateTime _windowStart;
  final Map<TrackSource, _FeedStats> _feeds = {};
  final Map<String, int> _lastCounts = {};

  /// Setiap fix dari feed (sebelum filter recordable di manajer).
  void onFix(TrackSource source, GeoPoint p) {
    final s = _feeds.putIfAbsent(source, _FeedStats.new);
    s.count++;
    if (!p.recordable) s.rejected++;
    final acc = p.accuracy;
    if (acc != null) s.accuracies.add(acc);
  }

  /// Teks ringkasan bila jendela [interval] sudah lewat DAN ada sesi merekam;
  /// selain itu null. Jendela direset setiap kali lewat.
  String? maybeSummary(DateTime now, Iterable<TrackingSession> sessions) {
    if (now.difference(_windowStart) < interval) return null;
    final minutes = now.difference(_windowStart).inMinutes;
    final recording = sessions.where((s) => s.isRecording).toList();

    String? text;
    if (recording.isNotEmpty) {
      final sources = recording.map((s) => s.source).toSet();
      final parts = <String>[
        '$minutes mnt',
        for (final src in TrackSource.values)
          if (sources.contains(src) || _feeds.containsKey(src))
            _feedText(src, _feeds[src]),
        for (final s in recording)
          '"${s.project.name}" +${s.pointCount - (_lastCounts[s.projectId] ?? 0)} '
              '(total ${s.pointCount})',
      ];
      text = parts.join(' · ');
    }

    _windowStart = now;
    _feeds.clear();
    _lastCounts
      ..clear()
      ..addEntries(sessions.map((s) => MapEntry(s.projectId, s.pointCount)));
    return text;
  }

  static String _feedText(TrackSource src, _FeedStats? s) {
    final label = src == TrackSource.emlid ? 'RTK' : 'HP';
    if (s == null || s.count == 0) return '$label 0 fix';
    final details = [
      if (s.rejected > 0) '${s.rejected} ditolak',
      if (s.accuracies.isNotEmpty)
        'median ±${_median(s.accuracies).toStringAsFixed(1)} m',
    ];
    return details.isEmpty
        ? '$label ${s.count} fix'
        : '$label ${s.count} fix (${details.join(', ')})';
  }

  static double _median(List<double> values) {
    final v = List.of(values)..sort();
    final mid = v.length ~/ 2;
    return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
  }
}

class _FeedStats {
  int count = 0;
  int rejected = 0;
  final List<double> accuracies = [];
}
