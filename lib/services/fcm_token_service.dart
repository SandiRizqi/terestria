import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class FCMTokenService {
  static final FCMTokenService _instance = FCMTokenService._internal();
  factory FCMTokenService() => _instance;
  FCMTokenService._internal();

  // Removed DeviceInfoPlugin dependency
  
  String? _deviceId;
  String? _lastRegisteredToken;
  
  static const String _prefKeyLastToken = 'last_fcm_token';
  static const String _prefKeyDeviceId = 'device_id';

  /// Initialize and get device ID
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get or create device ID
      _deviceId = prefs.getString(_prefKeyDeviceId);
      if (_deviceId == null) {
        _deviceId = await _generateDeviceId();
        await prefs.setString(_prefKeyDeviceId, _deviceId!);
      }
      
      // Get last registered token
      _lastRegisteredToken = prefs.getString(_prefKeyLastToken);
      
      print('📱 Device ID: $_deviceId');
      print('🔑 Last registered token: ${_lastRegisteredToken != null ? "exists" : "none"}');
    } catch (e) {
      print('❌ Error initializing FCM Token Service: $e');
    }
  }

  /// Register or update FCM token to backend
  Future<bool> registerToken(String fcmToken, String authToken) async {
    try {
      // Check if token already registered
      if (_lastRegisteredToken == fcmToken) {
        print('✅ Token already registered, skipping');
        return true;
      }

      if (_deviceId == null) {
        await initialize();
      }

      // Get device info
      final deviceName = await _getDeviceName();
      final osVersion = await _getOSVersion();
      final appVersion = await _getAppVersion();
      final platform = Platform.isAndroid ? 'android' : 'ios';

      print('📤 Registering FCM token to backend...');
      print('   Device ID: $_deviceId');
      print('   Platform: $platform');
      print('   Device: $deviceName');
      print('   OS: $osVersion');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.fcmTokenRegisterEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $authToken',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'device_id': _deviceId,
          'platform': platform,
          'device_name': deviceName,
          'app_version': appVersion,
          'os_version': osVersion,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Save last registered token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyLastToken, fcmToken);
        _lastRegisteredToken = fcmToken;
        
        final data = jsonDecode(response.body);
        print('✅ FCM Token registered successfully');
        print('   Response: ${data['message']}');
        return true;
      } else {
        print('❌ Failed to register FCM token: ${response.statusCode}');
        print('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error registering FCM token: $e');
      return false;
    }
  }

  /// Deactivate token on logout
  Future<bool> deactivateToken(String authToken) async {
    try {
      if (_deviceId == null) {
        await initialize();
      }

      print('📤 Deactivating FCM token...');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.fcmTokenDeactivateByDeviceEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $authToken',
        },
        body: jsonEncode({
          'device_id': _deviceId,
        }),
      );

      if (response.statusCode == 200) {
        // Clear saved token
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKeyLastToken);
        _lastRegisteredToken = null;
        
        final data = jsonDecode(response.body);
        print('✅ FCM token deactivated');
        print('   Response: ${data['message']}');
        return true;
      } else {
        print('❌ Failed to deactivate FCM token: ${response.statusCode}');
        print('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error deactivating FCM token: $e');
      return false;
    }
  }

  /// Deactivate all tokens (global logout)
  Future<bool> deactivateAllTokens(String authToken) async {
    try {
      print('📤 Deactivating all FCM tokens...');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.fcmTokenDeactivateAllEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $authToken',
        },
      );

      if (response.statusCode == 200) {
        // Clear saved token
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKeyLastToken);
        _lastRegisteredToken = null;
        
        final data = jsonDecode(response.body);
        print('✅ All FCM tokens deactivated');
        print('   Response: ${data['message']}');
        return true;
      } else {
        print('❌ Failed to deactivate all FCM tokens: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error deactivating all FCM tokens: $e');
      return false;
    }
  }

  /// Get list of user's FCM tokens
  Future<List<Map<String, dynamic>>?> getTokensList(String authToken) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.fcmTokenListEndpoint}'),
        headers: {
          'Authorization': 'Token $authToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        print('❌ Failed to get tokens list: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error getting tokens list: $e');
      return null;
    }
  }

  /// Generate unique device ID (using UUID stored in SharedPreferences)
  Future<String> _generateDeviceId() async {
    try {
      // Generate unique ID based on platform and timestamp
      final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomPart = timestamp.toString().substring(timestamp.toString().length - 8);
      return '${platform}_$randomPart';
    } catch (e) {
      print('❌ Error generating device ID: $e');
      return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Get device name (simple detection)
  Future<String> _getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        return 'Android Device';
      } else if (Platform.isIOS) {
        return 'iOS Device';
      }
      return 'Unknown Device';
    } catch (e) {
      print('❌ Error getting device name: $e');
      return 'Unknown Device';
    }
  }

  /// Get OS version (simple detection)
  Future<String> _getOSVersion() async {
    try {
      if (Platform.isAndroid) {
        return 'Android ${Platform.operatingSystemVersion}';
      } else if (Platform.isIOS) {
        return 'iOS ${Platform.operatingSystemVersion}';
      }
      return Platform.operatingSystemVersion;
    } catch (e) {
      print('❌ Error getting OS version: $e');
      return 'Unknown';
    }
  }

  /// Get app version (from package info or default)
  Future<String> _getAppVersion() async {
    try {
      // Return hardcoded version for now
      // You can update this manually or use package_info_plus later
      return '1.0.0';
    } catch (e) {
      print('❌ Error getting app version: $e');
      return '1.0.0';
    }
  }

  /// Get current device ID
  String? get deviceId => _deviceId;

  /// Get last registered token
  String? get lastRegisteredToken => _lastRegisteredToken;
}
