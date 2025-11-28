import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../config/api_config.dart';
import '../app_initializer.dart';

class AuthService {
  static const String _userKey = 'user_data';
  static const String _tokenKey = 'auth_token';
  static const String _isLoggedInKey = 'is_logged_in';

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
      
      // Save credentials locally
      await _saveCredentials(user);
      
      return AuthResult(
        success: true,
        message: 'Login successful (offline mode)',
        user: user,
      );
    }

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.authUrl),
        headers: ApiConfig.defaultHeaders,
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        // Parse response sesuai format backend Anda:
        // {
        //   "message": "Login successful",
        //   "username": "anugrah.sandi",
        //   "scope": [4, 6, 7, ...],
        //   "token": "13129765796f84d3e946e428879c1c328b129d6c"
        // }
        
        final user = User(
          id: data['username'] ?? username, // Gunakan username sebagai ID
          username: data['username'] ?? username,
          token: data['token'],
          scope: data['scope'] != null ? List<int>.from(data['scope']) : null,
        );
        
        // Save credentials
        await _saveCredentials(user);
        
        // Register FCM token after successful login
        if (user.token != null) {
          try {
            await AppInitializer().updateFCMAuthToken(user.token!);
            print('✅ FCM token registered after login');
          } catch (e) {
            print('⚠️ Failed to register FCM token: $e');
            // Don't fail login if FCM registration fails
          }
        }
        
        return AuthResult(
          success: true,
          message: data['message'] ?? 'Login successful',
          user: user,
        );
      } else {
        final errorData = jsonDecode(response.body);
        return AuthResult(
          success: false,
          message: errorData['message'] ?? 'Login failed',
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Connection error: $e',
      );
    }
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
  Future<void> logout() async {
    // Deactivate FCM token before logout
    try {
      final token = await getToken();
      if (token != null) {
        await AppInitializer().deactivateFCMToken(token);
        print('✅ FCM token deactivated on logout');
      }
    } catch (e) {
      print('⚠️ Failed to deactivate FCM token: $e');
      // Continue with logout even if FCM deactivation fails
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    await prefs.setBool(_isLoggedInKey, false);
    
    // Clear cache
    _cachedToken = null;
    _cachedUser = null;
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
