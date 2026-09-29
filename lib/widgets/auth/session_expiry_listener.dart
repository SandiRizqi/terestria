import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';

/// Pasang di root app: saat server menolak token (HTTP 401), tampilkan dialog
/// login ulang untuk user yang SAMA. Dulu satu-satunya jalan adalah logout —
/// yang menghapus semua project, data, dan foto yang belum tersinkron.
class SessionExpiryListener extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final AuthService? auth;

  const SessionExpiryListener({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.auth,
  });

  @override
  State<SessionExpiryListener> createState() => _SessionExpiryListenerState();
}

class _SessionExpiryListenerState extends State<SessionExpiryListener> {
  late final AuthService _auth = widget.auth ?? AuthService();
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _auth.sessionExpired.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    _auth.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    if (_showing || !_auth.isSessionExpired) return;
    // Sinyal bisa datang di tengah build/navigasi → tampilkan setelah frame.
    // Minta frame: layar statis tak menjadwalkan frame sendiri.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _show())
      ..ensureVisualUpdate();
  }

  Future<void> _show() async {
    if (_showing || !mounted || !_auth.isSessionExpired) return;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      logWarn('Session expired but no navigator to show the re-login dialog',
          tag: 'AUTH');
      _auth.dismissSessionExpired(snooze: Duration.zero);
      return;
    }
    _showing = true;
    try {
      final ok = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => SessionExpiredDialog(auth: _auth),
      );
      if (ok == true) {
        final c = widget.navigatorKey.currentContext;
        if (c != null && c.mounted) {
          showInfoFeedback(c, 'Signed in again. You can continue syncing.',
              success: true);
        }
      }
    } catch (e, st) {
      logError('Re-login dialog failed', error: e, stack: st, tag: 'AUTH');
      _auth.dismissSessionExpired();
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dialog login ulang: username terkunci, hanya kata sandi. "Later" menunda
/// (data tetap aman di HP); "Sign in" memanggil [AuthService.reauthenticate].
class SessionExpiredDialog extends StatefulWidget {
  final AuthService auth;
  const SessionExpiredDialog({super.key, required this.auth});

  @override
  State<SessionExpiredDialog> createState() => _SessionExpiredDialogState();
}

class _SessionExpiredDialogState extends State<SessionExpiredDialog> {
  final _password = TextEditingController();
  String? _username;
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.auth.getUser().then((u) {
      if (mounted) setState(() => _username = u?.username);
    }).catchError((Object e, StackTrace st) {
      logWarn('Could not read the signed-in user', error: e, stack: st,
          tag: 'AUTH');
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.auth.reauthenticate(pw);
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = result.message;
        });
      }
    } catch (e, st) {
      logError('Re-login failed unexpectedly', error: e, stack: st,
          tag: 'AUTH');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  void _later() {
    widget.auth.dismissSessionExpired();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.lock_clock_rounded,
            color: Colors.orange, size: 32),
        title: const Text('Session expired'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The server no longer accepts your sign-in. Your projects, '
                'records and photos are safe on this device — sign in again '
                'to keep syncing. Do NOT log out: logging out deletes '
                'unsynced data.',
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                child: Text(_username ?? '…'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  errorMaxLines: 4,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _later,
            child: const Text('Later'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
