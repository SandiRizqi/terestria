import 'dart:async';
import 'dart:io';

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

  // Manual check (untuk digunakan sebelum sync)
  Future<bool> checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
