import 'package:flutter/material.dart';

import '../../services/logging/log_exporter.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/share_origin.dart';
import '../../utils/ui_feedback.dart';

/// Ditampilkan bila inisialisasi app gagal (mis. database tak bisa dibuka
/// karena penyimpanan penuh). Dulu `runApp` tak pernah dipanggil sehingga app
/// macet di splash native tanpa penjelasan.
class InitFailureApp extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const InitFailureApp({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terestria',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _InitFailureScreen(error: error, onRetry: onRetry),
    );
  }
}

class _InitFailureScreen extends StatefulWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _InitFailureScreen({required this.error, required this.onRetry});

  @override
  State<_InitFailureScreen> createState() => _InitFailureScreenState();
}

class _InitFailureScreenState extends State<_InitFailureScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    logInfo('Retrying app start after init failure', tag: 'APP');
    try {
      await widget.onRetry();
    } catch (e, st) {
      logError('Retry after init failure failed',
          tag: 'APP', error: e, stack: st);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _shareLog() async {
    final origin = shareOriginFor(context);
    try {
      await exportAndShareLogs(sharePositionOrigin: origin);
    } catch (e, st) {
      if (!mounted) return;
      showErrorFeedback(context, 'Could not share the diagnostic log',
          error: e, stack: st, tag: 'APP');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageFull = isStorageFullError(widget.error);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                storageFull ? Icons.sd_storage_outlined : Icons.error_outline,
                size: 72,
                color: Colors.orange.shade800,
              ),
              const SizedBox(height: 16),
              const Text(
                'Terestria could not start',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                friendlyErrorMessage(widget.error),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your saved data has not been deleted.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _busy ? null : _retry,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _shareLog,
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Share diagnostic log'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
