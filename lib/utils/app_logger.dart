import 'package:flutter/foundation.dart';

/// Logging ringan untuk service — aman dipakai di background isolate.
///
/// [logDebug] hanya mencetak di debug build. Dipakai untuk log verbose di
/// hot path (GPS per-reading, routing) supaya release build tidak spam
/// logcat dan tidak membuang CPU.
///
/// [logError] tetap mencetak di release, untuk jalur error yang perlu
/// terlihat di logcat produksi (Crashlytics tetap kanal pelaporan utama).
void logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

void logError(String message) {
  debugPrint(message);
}
