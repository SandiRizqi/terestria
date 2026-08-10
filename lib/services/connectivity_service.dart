import 'dart:async';
import 'dart:io';
import '../config/api_config.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;
  
  bool _isOnline = false;
  bool get isOnline => _isOnline;
  
  Timer? _timer;

  // Start monitoring connectivity
  void startMonitoring() {
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnection();
    });
  }

  // Stop monitoring
  void stopMonitoring() {
    _timer?.cancel();
    _connectivityController.close();
  }

  // Check internet connection
  Future<void> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(true);
      } else {
        _updateStatus(false);
      }
    } on SocketException catch (_) {
      _updateStatus(false);
    } on TimeoutException catch (_) {
      _updateStatus(false);
    } catch (_) {
      _updateStatus(false);
    }
  }

  void _updateStatus(bool status) {
    if (_isOnline != status) {
      _isOnline = status;
      _connectivityController.add(_isOnline);
    }
  }

  // Manual check internet umum (DNS google.com)
  Future<bool> checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah HOST SERVER sebenarnya (mis. django.tap-agri.com) bisa
  /// di-resolve. Dipakai sebagai pre-flight sebelum sync — internet umum
  /// bisa saja ada (google jalan) tapi domain server gagal di-resolve.
  Future<bool> checkServerReachable() async {
    try {
      final host = Uri.parse(ApiConfig.baseUrl).host;
      if (host.isEmpty) return false;
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
