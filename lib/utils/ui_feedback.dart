import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// Umpan balik UI yang konsisten: pesan ramah untuk user, detail teknis ke
/// berkas log (bisa dibagikan dari Settings → Diagnostic log). UI tidak
/// pernah menampilkan exception mentah (`'Error: $e'`).

/// errno "No space left on device" (Linux/Android = 28, Darwin/iOS = 28).
const int _enospc = 28;

/// True bila [error] disebabkan penyimpanan penuh (file atau SQLite).
bool isStorageFullError(Object error) {
  if (error is FileSystemException) {
    if (error.osError?.errorCode == _enospc) return true;
    final msg = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    if (msg.contains('no space left')) return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('database or disk is full') ||
      text.contains('sqlite_full') ||
      text.contains('no space left on device') ||
      text.contains('disk full');
}

/// Pesan ramah (English) untuk error umum di lapangan.
String friendlyErrorMessage(Object error) {
  if (isStorageFullError(error)) {
    return 'Storage is full. Free up space on this phone (e.g. delete old '
        'photos, videos or offline maps), then try again.';
  }
  if (error is SocketException || error is http.ClientException) {
    return 'No connection. Check your mobile data or Wi-Fi and try again.';
  }
  if (error is TimeoutException) {
    return 'The operation timed out. Check your connection and try again.';
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('permission') || code.contains('denied')) {
      return 'Permission denied. Allow the permission in the phone settings '
          'and try again.';
    }
    if (code.contains('camera')) {
      return 'The camera is not available right now. Close other camera '
          'apps and try again.';
    }
  }
  if (error is FileSystemException) {
    return 'A file could not be read or written. Details were saved to the '
        'diagnostic log.';
  }
  if (error is FormatException) {
    return 'The data could not be read. Details were saved to the '
        'diagnostic log.';
  }
  return 'Something went wrong. Details were saved to the diagnostic log.';
}

/// Catat [error] ke log lalu kembalikan kalimat ramah "[what]. <sebab>" —
/// untuk tempat yang menyusun SnackBar/dialog/status sendiri.
String loggedErrorMessage(String what, Object error,
    {StackTrace? stack, String tag = 'UI'}) {
  logError(what, tag: tag, error: error, stack: stack);
  return '$what. ${friendlyErrorMessage(error)}';
}

/// Catat [error] lalu tampilkan snackbar merah. [message] = konteks singkat
/// ("Could not save the record"); penjelasan ramah ditambahkan otomatis.
///
/// [log] false bila error sudah dicatat pemanggil (mis. lewat Crashlytics
/// service yang juga menulis ke berkas log) agar tak tercatat dua kali.
void showErrorFeedback(
  BuildContext context,
  String message, {
  Object? error,
  StackTrace? stack,
  String tag = 'UI',
  bool log = true,
}) {
  if (log) logError(message, tag: tag, error: error, stack: stack);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final detail = error == null ? null : friendlyErrorMessage(error);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(detail == null ? message : '$message. $detail'),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
}

/// Snackbar informasi (hijau untuk sukses, oranye untuk peringatan).
void showInfoFeedback(
  BuildContext context,
  String message, {
  bool success = false,
  bool warning = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: success
          ? Colors.green.shade700
          : (warning ? Colors.orange.shade800 : null),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      action: action,
    ));
}
