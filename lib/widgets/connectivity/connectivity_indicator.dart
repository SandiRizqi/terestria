import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';

class ConnectivityIndicator extends StatefulWidget {
  final bool showLabel;
  final double iconSize;
  
  const ConnectivityIndicator({
    Key? key,
    this.showLabel = true,
    this.iconSize = 20,
  }) : super(key: key);

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() => _isOnline = isOnline);
      }
    });

    try {
      final isOnline = await _connectivityService.checkConnection();
      if (mounted) {
        setState(() => _isOnline = isOnline);
      }
    } catch (e) {
      // Handle error silently, default to offline
      if (mounted) {
        setState(() => _isOnline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isOnline ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isOnline ? Colors.green : Colors.red,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isOnline ? Icons.wifi : Icons.wifi_off,
              color: _isOnline ? Colors.green : Colors.red,
              size: widget.iconSize,
            ),
            const SizedBox(width: 6),
            Text(
              _isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                color: _isOnline ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      return Icon(
        _isOnline ? Icons.wifi : Icons.wifi_off,
        color: _isOnline ? Colors.green : Colors.red,
        size: widget.iconSize,
      );
    }
  }
}
