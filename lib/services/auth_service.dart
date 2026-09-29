import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../config/api_config.dart';
import '../app_initializer.dart';
import 'scope_topic_service.dart';

import '../utils/app_logger.dart';
class AuthService {
  static const String _userKey = 'user_data';
  static const String _tokenKey = 'auth_token';
  static const String _isLoggedInKey = 'is_logged_in';

  final _scopeTopicService = ScopeTopicService();

  // Singleton pattern untuk memastikan satu instance
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Cache token dan user di memory untuk akses cepat
  String? _cachedToken;
  User? _cachedUser;

  // Check if auth is required
  bool get isAuthRequired => ApiConfig.authUrl.isNotEmpty;

  // Get token (prioritas dari cache, lalu dari storage)
  Future<String?> getToken() async {
    if (_cachedToken != null) {
      return _cachedToken;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  // Get user (prioritas dari cache, lalu dari storage)
  Future<User?> getUser() async {
    if (_cachedUser != null) {
      return _cachedUser;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    
    if (userJson != null) {
      _cachedUser = User.fromJson(jsonDecode(userJson));
      return _cachedUser;
    }
    return null;
  }

  // Login with FCM token registration
  Future<AuthResult> login(String username, String password) async {
    // If no authUrl, accept any credentials without backend validation
    if (!isAuthRequired) {
      // Create local user with provided username
      final user = User(
        id: 'local_${username}',
        username: username,
      );

      await _saveCredentials(user);

      return AuthResult(
        success: true,
        message: 'Login successful (offline mode)',
        user: user,
      );
    }

    final auth = await _authenticate(username, password);
    final user = auth.user;
    if (user == null) return auth;

    // Save credentials
    await _saveCredentials(user);
    _clearSessionExpiry();
    logInfo('Login succeeded for ${user.username}', tag: 'AUTH');

    await _afterLogin(user);
    return auth;
  }

  /// Minta token ke server TANPA menyimpan apa pun. Pesan error ramah untuk
  /// UI; detail teknis ke log.
  Future<AuthResult> _authenticate(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authUrl),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(ApiConfig.loginTimeout);

      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        data = null; // mis. halaman HTML proxy / hotspot
      }

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data != null &&
          data['token'] != null) {
        // Format backend:
        // {"message": "Login successful", "username": "anugrah.sandi",
        //  "scope": [4, 6, 7, ...], "token": "1312…"}
        final user = User(
          id: data['username'] ?? username, // Gunakan username sebagai ID
          username: data['username'] ?? username,
          token: data['token'],
          scope: data['scope'] is List
              ? (data['scope'] as List)
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .toList()
              : null,
        );
        return AuthResult(
          success: true,
          message: data['message']?.toString() ?? 'Login successful',
          user: user,
        );
      }

      logWarn(
          'Login rejected: HTTP ${response.statusCode}'
          '${data == null ? ' (non-JSON response)' : ''}',
          tag: 'AUTH');
      final String message;
      if (data != null && data['message'] != null) {
        message = data['message'].toString();
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        message = 'Incorrect username or password.';
      } else if (data == null && response.statusCode < 300) {
        message = 'Unexpected response from the server. If you are on a '
            'hotspot or office Wi-Fi, sign in to the network first.';
      } else {
        message = 'Login failed (server error ${response.statusCode}). '
            'Please try again later.';
      }
      return AuthResult(success: false, message: message);
    } on TimeoutException catch (e) {
      logWarn('Login timed out after ${ApiConfig.loginTimeout.inSeconds}s: $e',
          tag: 'AUTH');
      return AuthResult(
        success: false,
        message: 'The server did not respond in time. '
            'Check your connection and try again.',
      );
    } on SocketException catch (e) {
      logWarn('Login failed: no connection ($e)', tag: 'AUTH');
      return AuthResult(
        success: false,
        message: 'No connection to the server. Check your internet connection.',
      );
    } on http.ClientException catch (e) {
      logWarn('Login failed: client error ($e)', tag: 'AUTH');
      return AuthResult(
        success: false,
        message: 'No connection to the server. Check your internet connection.',
      );
    } catch (e, st) {
      logError('Login failed unexpectedly', tag: 'AUTH', error: e, stack: st);
      return AuthResult(
        success: false,
        message: 'Login failed. Please try again.',
      );
    }
  }

  /// FCM token & topik scope setelah login/re-login. Gagal tak menggagalkan login.
  Future<void> _afterLogin(User user) async {
    if (user.token != null) {
      try {
        await AppInitializer().updateFCMAuthToken(user.token!);
        logDebug('✅ FCM token registered after login', tag: 'AUTH');
      } catch (e) {
        logWarn('⚠️ Failed to register FCM token: $e', tag: 'AUTH');
      }
    }
    // Sync FCM topic subscriptions based on scope — fire-and-forget di
    // background (antrean serial di service) supaya login tidak menunggu
    // round-trip FCM per scope. Gagal pun tak menggagalkan login.
    _scopeTopicService.syncTopicsInBackground(user.scope ?? []);
  }

  // ─── Sesi kedaluwarsa (HTTP 401) ─────────────────────────────────────────

  /// Naik setiap kali server menolak token (HTTP 401). Didengar oleh
  /// `SessionExpiryListener` di root app yang menampilkan dialog login ulang.
  /// Logout TIDAK dipakai di sini karena logout menghapus semua data lokal.
  final ValueNotifier<int> sessionExpired = ValueNotifier<int>(0);
  bool _sessionExpiredPending = false;
  bool _tokenRejected = false;
  DateTime? _reloginSnoozedUntil;

  /// True selama dialog login ulang belum diselesaikan.
  bool get isSessionExpired => _sessionExpiredPending;

  /// True sejak server menolak token sampai login ulang berhasil — dipakai UI
  /// sync untuk menawarkan "Sign in again" meski dialog ditunda.
  bool get tokenRejected => _tokenRejected;

  /// Dipanggil [ApiService] saat server membalas 401 untuk request bertoken.
  /// Satu sinyal per kejadian (tak membanjiri UI bila banyak request gagal);
  /// setelah "Later" dialog tak muncul lagi sampai jeda [dismissSessionExpired]
  /// habis — kecuali user memintanya lewat [requestReLogin].
  void reportUnauthorized(String endpoint) {
    if (_cachedToken == null && _cachedUser == null) return;
    if (_sessionExpiredPending) return;
    final firstRejection = !_tokenRejected;
    _tokenRejected = true;
    final snoozed = _reloginSnoozedUntil != null &&
        DateTime.now().isBefore(_reloginSnoozedUntil!);
    if (snoozed) {
      logDebug('401 at $endpoint (re-login prompt snoozed)', tag: 'AUTH');
      return;
    }
    if (firstRejection) {
      logWarn('Server rejected the session token (401) at $endpoint',
          tag: 'AUTH');
    }
    _sessionExpiredPending = true;
    sessionExpired.value++;
  }

  /// User menunda login ulang ("Later"): dialog tak muncul lagi selama
  /// [snooze] agar sync otomatis tak terus memunculkannya.
  void dismissSessionExpired(
      {Duration snooze = const Duration(minutes: 10)}) {
    _sessionExpiredPending = false;
    _reloginSnoozedUntil = DateTime.now().add(snooze);
    logInfo('Re-login postponed for ${snooze.inMinutes} min', tag: 'AUTH');
  }

  /// Tampilkan dialog login ulang sekarang (tombol "Sign in again").
  void requestReLogin() {
    _reloginSnoozedUntil = null;
    if (_sessionExpiredPending) return;
    _sessionExpiredPending = true;
    sessionExpired.value++;
  }

  void _clearSessionExpiry() {
    _sessionExpiredPending = false;
    _tokenRejected = false;
    _reloginSnoozedUntil = null;
  }

  @visibleForTesting
  void debugResetSessionExpiry() => _clearSessionExpiry();

  /// Login ulang untuk user yang SAMA; project, data, dan foto lokal tetap
  /// utuh. Menolak bila server mengembalikan akun lain.
  Future<AuthResult> reauthenticate(String password) async {
    final current = await getUser();
    if (current == null) {
      return AuthResult(success: false, message: 'No signed-in user.');
    }
    final auth = await _authenticate(current.username, password);
    final user = auth.user;
    if (user == null) return auth;
    if (user.username.trim().toLowerCase() !=
        current.username.trim().toLowerCase()) {
      logWarn('Re-login returned a different account; ignored', tag: 'AUTH');
      return AuthResult(
        success: false,
        message: 'Signed in as a different account. Use ${current.username}.',
      );
    }
    await _saveCredentials(
        current.copyWith(token: user.token, scope: user.scope));
    _clearSessionExpiry();
    logInfo('Re-login succeeded for ${current.username}', tag: 'AUTH');
    await _afterLogin(user);
    return auth;
  }

  // Save credentials locally
  Future<void> _saveCredentials(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    if (user.token != null) {
      await prefs.setString(_tokenKey, user.token!);
      _cachedToken = user.token; // Update cache
    }
    await prefs.setBool(_isLoggedInKey, true);
    _cachedUser = user; // Update cache
  }

  // Get saved user (deprecated, gunakan getUser())
  @Deprecated('Use getUser() instead')
  Future<User?> getSavedUser() async {
    return getUser();
  }

  // Get saved token (deprecated, gunakan getToken())
  @Deprecated('Use getToken() instead')
  Future<String?> getSavedToken() async {
    return getToken();
  }

  // Check if logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Logout with FCM token deactivation
  // Local state dibersihkan dulu (instan) → FCM cleanup jalan fire-and-forget.
  // [waitForCleanup]: tunggu lepas topic FCM & deaktivasi token selesai —
  // dipakai reset app agar prefs (daftar topic) tak dihapus sebelum cleanup.
  Future<void> logout({bool waitForCleanup = false}) async {
    // 1. Ambil token sebelum cache dihapus (butuh untuk FCM cleanup)
    final tokenToDeactivate = _cachedToken ??
        (await SharedPreferences.getInstance()).getString(_tokenKey);

    // 2. Clear local state DULU — ini yang membuat logout terasa instan
    _cachedToken = null;
    _cachedUser = null;
    _clearSessionExpiry();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    await prefs.setBool(_isLoggedInKey, false);

    // 3. FCM cleanup jalan di background (fire-and-forget), tidak blokir UI
    final cleanup = _cleanupFCMAsync(tokenToDeactivate);
    if (waitForCleanup) await cleanup;
  }

  /// Jalankan FCM unsubscribe + deactivate di background.
  /// Tidak di-await oleh logout biasa supaya terasa instan.
  Future<void> _cleanupFCMAsync(String? token) {
    return Future(() async {
      try {
        // Lewat antrean serial service — tak balapan dengan syncTopics milik
        // login berikutnya bila user logout lalu login cepat.
        await _scopeTopicService.unsubscribeAllInBackground();
        logDebug('✅ FCM scope topics unsubscribed on logout', tag: 'AUTH');
      } catch (e) {
        logWarn('⚠️ Failed to unsubscribe FCM topics: $e', tag: 'AUTH');
      }

      try {
        if (token != null) {
          await AppInitializer().deactivateFCMToken(token);
          logDebug('✅ FCM token deactivated on logout', tag: 'AUTH');
        }
      } catch (e) {
        logWarn('⚠️ Failed to deactivate FCM token: $e', tag: 'AUTH');
      }
    });
  }

  // Verify token (optional - call backend to verify)
  Future<bool> verifyToken() async {
    // If auth not required, just check if user is logged in
    if (!isAuthRequired) {
      return await isLoggedIn();
    }
    
    final token = await getToken();
    if (token == null) return false;

    // TODO: Add token verification endpoint if backend supports it
    // For now, just check if token exists
    return true;
  }
}

class AuthResult {
  final bool success;
  final String message;
  final User? user;

  AuthResult({
    required this.success,
    required this.message,
    this.user,
  });
}
