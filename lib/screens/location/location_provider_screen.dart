import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/location_service.dart';
import '../../models/geo_data_model.dart';
import 'dart:async';

class LocationProviderScreen extends StatefulWidget {
  const LocationProviderScreen({Key? key}) : super(key: key);

  @override
  State<LocationProviderScreen> createState() => _LocationProviderScreenState();
}

class _LocationProviderScreenState extends State<LocationProviderScreen> {
  final LocationService _locationService = LocationService();
  final TextEditingController _hostController = TextEditingController(text: '192.168.42.1');
  final TextEditingController _portController = TextEditingController(text: '9090');
  
  LocationProvider _selectedProvider = LocationProvider.phone;
  CoordinateFormat _coordinateFormat = CoordinateFormat.llh;
  FixQuality _requiredFixQuality = FixQuality.any;
  
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isTesting = false;
  bool _isReceivingData = false; // NEW: track if data is being received
  DateTime? _lastDataReceived; // NEW: timestamp of last data
  String _consoleLog = '';
  GeoPoint? _currentLocation;
  String? _fixStatus;
  String? _satelliteCount;
  StreamSubscription<GeoPoint>? _locationSubscription;
  StreamSubscription<String>? _consoleSubscription;

  @override
  void initState() {
    super.initState();
    _listenToConsoleUpdates();
    _loadSavedSettings();
  }
  
  Future<void> _loadSavedSettings() async {
    // Load saved location settings
    await _locationService.loadLocationSettings();
    
    // Load Emlid connection settings
    final savedEmlidSettings = await _locationService.loadEmlidConnectionSettings();
    
    // Update UI with loaded settings
    if (mounted) {
      setState(() {
        _selectedProvider = _locationService.currentProvider;
        _requiredFixQuality = _locationService.currentFixQuality;
        
        // Update Emlid connection fields if saved
        if (savedEmlidSettings['host'] != null) {
          _hostController.text = savedEmlidSettings['host']!;
        }
        if (savedEmlidSettings['port'] != null) {
          _portController.text = savedEmlidSettings['port']!;
        }
        if (savedEmlidSettings['format'] != null) {
          final formatIndex = int.tryParse(savedEmlidSettings['format']!);
          if (formatIndex != null && formatIndex < CoordinateFormat.values.length) {
            _coordinateFormat = CoordinateFormat.values[formatIndex];
          }
        }
        
        // Check if Emlid is already connected
        _isConnected = _locationService.isEmlidConnected;
        _isReceivingData = _locationService.isEmlidStreaming;
        _lastDataReceived = _locationService.lastEmlidDataTime;
      });
      
      print('DEBUG UI: Loaded provider=${_selectedProvider.name}, fix=${_requiredFixQuality.name}');
      print('DEBUG UI: Emlid settings - host=${_hostController.text}, port=${_portController.text}, format=${_coordinateFormat.name}');
      print('DEBUG UI: Emlid connected=${_isConnected}, streaming=${_isReceivingData}');
      
      // Auto-reconnect if Emlid was selected but not connected
      if (_selectedProvider == LocationProvider.emlid && 
          !_isConnected && 
          savedEmlidSettings['host'] != null && 
          savedEmlidSettings['port'] != null) {
        print('DEBUG UI: Auto-reconnecting to Emlid...');
        _showSuccess('Auto-reconnecting to Emlid GPS...');
        await _connectToEmlid();
      }
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _consoleSubscription?.cancel();
    _hostController.dispose();
    _portController.dispose();
    // DON'T disconnect Emlid here - keep connection alive for data collection
    // Only disconnect when user explicitly disconnects or changes provider
    super.dispose();
  }

  void _listenToConsoleUpdates() {
    _consoleSubscription = _locationService.consoleStream.listen((log) {
      if (mounted) {
        setState(() {
          _consoleLog += '$log\n';
          
          // Track if we're receiving data
          if (log.contains('< ') || log.contains('Valid position')) {
            _isReceivingData = true;
            _lastDataReceived = DateTime.now();
          }
          
          // Keep only last 2000 characters
          if (_consoleLog.length > 2000) {
            _consoleLog = _consoleLog.substring(_consoleLog.length - 2000);
          }
        });
      }
    });
    
    // Check periodically if data has stopped coming
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_isConnected && _lastDataReceived != null) {
        final timeSinceLastData = DateTime.now().difference(_lastDataReceived!);
        if (timeSinceLastData.inSeconds > 10) {
          setState(() {
            _isReceivingData = false;
          });
        }
      }
    });
  }

  Future<void> _connectToEmlid() async {
    if (_hostController.text.isEmpty || _portController.text.isEmpty) {
      _showError('Please enter host and port');
      return;
    }

    setState(() {
      _isConnecting = true;
      _consoleLog = '';
    });

    try {
      final host = _hostController.text.trim();
      final portText = _portController.text.trim();
      final port = int.tryParse(portText);
      
      print('DEBUG: Attempting to connect to $host:$portText (parsed as $port)');
      
      if (port == null || port < 1 || port > 65535) {
        throw Exception('Invalid port number: $portText');
      }

      final success = await _locationService.connectEmlidTCP(
        host: host,
        port: port,
        coordinateFormat: _coordinateFormat,
      );

      if (mounted) {
        setState(() {
          _isConnected = success;
          _isConnecting = false;
        });

        if (success) {
          _showSuccess('Connected to Emlid GPS');
        } else {
          _showError('Failed to connect to Emlid GPS');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
        });
        _showError('Connection error: ${e.toString()}');
      }
    }
  }

  Future<void> _disconnectFromEmlid() async {
    await _locationService.disconnectEmlidTCP();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isReceivingData = false;
        _lastDataReceived = null;
        _consoleLog = '';
        _currentLocation = null;
        _fixStatus = null;
        _satelliteCount = null;
      });
      _showSuccess('Disconnected from RTK GPS');
    }
  }

  Future<void> _testConnection() async {
    if (_selectedProvider == LocationProvider.emlid && !_isConnected) {
      _showError('Please connect to RTK GPS first');
      return;
    }

    setState(() {
      _isTesting = true;
      _currentLocation = null;
      _fixStatus = null;
      _satelliteCount = null;
    });

    try {
      _locationSubscription?.cancel();
      
      if (_selectedProvider == LocationProvider.phone) {
        // Test phone GPS
        final location = await _locationService.getCurrentLocation();
        if (location != null && mounted) {
          setState(() {
            _currentLocation = location;
            _fixStatus = 'GPS';
            _isTesting = false;
          });
          _showSuccess('Phone GPS working correctly');
        } else {
          throw Exception('Failed to get phone GPS location');
        }
      } else {
        // Test Emlid GPS - get continuous stream
        _locationSubscription = _locationService.trackEmlidLocation().listen(
          (location) {
            if (mounted) {
              setState(() {
                _currentLocation = location;
                _fixStatus = location.fixQuality;
                _satelliteCount = location.satelliteCount?.toString();
                _isTesting = false;
              });
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _isTesting = false;
              });
              _showError('Error: ${error.toString()}');
            }
          },
        );

        // Wait a bit to receive data
        await Future.delayed(const Duration(seconds: 3));
        
        if (mounted && _currentLocation == null) {
          setState(() {
            _isTesting = false;
          });
          _showError('No data received from RTK GPS');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
        _showError('Test failed: ${e.toString()}');
      }
    }
  }

  Future<void> _saveSettings() async {
    // Stop testing stream if active
    _locationSubscription?.cancel();

    try {
      await _locationService.setLocationProvider(
        provider: _selectedProvider,
        requiredFixQuality: _requiredFixQuality,
      );

      if (mounted) {
        _showSuccess('Location provider settings saved');
        // 🔧 Return true to notify caller that settings changed
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save settings: ${e.toString()}');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCommonIPs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Common Emlid IPs'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a common IP or enter manually:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildIPOption('192.168.42.1', 'Emlid Hotspot (default)'),
            _buildIPOption('192.168.1.1', 'Router default'),
            const Divider(height: 24),
            const Text(
              'Tip: Check your WiFi settings to find the router/gateway IP',
              style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  Widget _buildIPOption(String ip, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _hostController.text = ip;
          });
          Navigator.pop(context);
          _showSuccess('IP set to $ip');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.router, size: 20, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ip,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  bool _checkFixQuality() {
    if (_currentLocation == null || _currentLocation!.fixQuality == null) {
      return false;
    }

    switch (_requiredFixQuality) {
      case FixQuality.any:
        return true;
      case FixQuality.autonomous:
        return _currentLocation!.fixQuality == 'autonomous' ||
               _currentLocation!.fixQuality == 'float' ||
               _currentLocation!.fixQuality == 'fix';
      case FixQuality.float:
        return _currentLocation!.fixQuality == 'float' ||
               _currentLocation!.fixQuality == 'fix';
      case FixQuality.fix:
        return _currentLocation!.fixQuality == 'fix';
    }
  }

  Color _getFixQualityColor() {
    if (_currentLocation?.fixQuality == null) return Colors.grey;
    
    switch (_currentLocation!.fixQuality?.toLowerCase()) {
      case 'fix':
        return Colors.green;
      case 'float':
        return Colors.orange;
      case 'autonomous':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Provider'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Provider Selection
            _buildSectionTitle('Location Source', Icons.satellite_alt),
            const SizedBox(height: 12),
            _buildProviderCard(
              provider: LocationProvider.phone,
              icon: Icons.smartphone,
              title: 'Phone GPS',
              subtitle: 'Use built-in phone GPS',
            ),
            const SizedBox(height: 12),
            _buildProviderCard(
              provider: LocationProvider.emlid,
              icon: Icons.router,
              title: 'RTK GPS',
              subtitle: 'Connect via TCP/IP network',
            ),
            
            // Emlid Connection Settings
            if (_selectedProvider == LocationProvider.emlid) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('Emlid Connection', Icons.settings_ethernet),
              const SizedBox(height: 8),
              // Helper text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Make sure your phone is connected to the RTK WiFi. '
                        'Check the  IP in ReachView app or WiFi settings.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // IP Address field
                      TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: 'Host/IP Address',
                          hintText: '192.168.42.1',
                          prefixIcon: const Icon(Icons.dns),
                          border: const OutlineInputBorder(),
                          helperText: 'Emlid hotspot usually: 192.168.42.1',
                          helperMaxLines: 1,
                          helperStyle: const TextStyle(fontSize: 11),
                          suffixIcon: !_isConnected ? IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            tooltip: 'Use common IPs',
                            onPressed: () {
                              _showCommonIPs();
                            },
                          ) : null,
                        ),
                        keyboardType: TextInputType.text,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        enabled: !_isConnected,
                      ),
                      const SizedBox(height: 16),
                      // Port field
                      TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '9090',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                          helperText: 'Common ports: 9090, 5000',
                          helperMaxLines: 1,
                          helperStyle: TextStyle(fontSize: 11),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        enabled: !_isConnected,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<CoordinateFormat>(
                        value: _coordinateFormat,
                        decoration: const InputDecoration(
                          labelText: 'Data Format',
                          prefixIcon: Icon(Icons.code),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: CoordinateFormat.nmea,
                            child: Text('NMEA (Standard GPS)'),
                          ),
                          DropdownMenuItem(
                            value: CoordinateFormat.llh,
                            child: Text('LLH (Lat/Lon/Height)'),
                          ),
                          DropdownMenuItem(
                            value: CoordinateFormat.xyz,
                            child: Text('XYZ (ECEF Coordinates)'),
                          ),
                        ],
                        onChanged: _isConnected ? null : (value) {
                          if (value != null) {
                            setState(() {
                              _coordinateFormat = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isConnecting
                                  ? null
                                  : (_isConnected ? _disconnectFromEmlid : _connectToEmlid),
                              icon: _isConnecting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(_isConnected ? Icons.close : Icons.link),
                              label: Text(_isConnecting
                                  ? 'Connecting...'
                                  : (_isConnected ? 'Disconnect' : 'Connect')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isConnected ? Colors.red : Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Connection Status Indicators
                      if (_isConnected) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isReceivingData ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isReceivingData ? Colors.green : Colors.orange,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isReceivingData ? Icons.check_circle : Icons.warning,
                                color: _isReceivingData ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isReceivingData ? 'Data Streaming' : 'Connected but No Data',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _isReceivingData ? Colors.green[800] : Colors.orange[800],
                                      ),
                                    ),
                                    if (_lastDataReceived != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Last data: ${_formatTimeSince(_lastDataReceived!)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                    if (!_isReceivingData) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Check: Position Output enabled in ReachView?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Connection info
                      if (_hostController.text.isNotEmpty && _portController.text.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Will connect to ${_hostController.text.trim()}:${_portController.text.trim()}',
                                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Console Log
              if (_consoleLog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.grey[900],
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    height: 150,
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _consoleLog,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
            
            // Fix Quality Settings
            const SizedBox(height: 24),
            _buildSectionTitle('Position Quality', Icons.verified),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Required Fix Quality:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<FixQuality>(
                      value: _requiredFixQuality,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.gps_fixed),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: FixQuality.any,
                          child: Text('Any (Accept all positions)'),
                        ),
                        DropdownMenuItem(
                          value: FixQuality.autonomous,
                          child: Text('Autonomous or better'),
                        ),
                        DropdownMenuItem(
                          value: FixQuality.float,
                          child: Text('Float or better (~dm accuracy)'),
                        ),
                        DropdownMenuItem(
                          value: FixQuality.fix,
                          child: Text('Fixed only (~cm accuracy)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _requiredFixQuality = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Points will only be recorded when fix quality meets this requirement',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Test Connection
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            
            // Location Data Display
            if (_currentLocation != null) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('Current Position', Icons.location_on),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Fix Status
                      if (_fixStatus != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.gps_fixed, size: 18),
                                SizedBox(width: 8),
                                Text('Fix Quality:', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getFixQualityColor(),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _fixStatus!.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                      ],
                      
                      // Coordinates
                      _buildDataRow('Latitude', '${_currentLocation!.latitude.toStringAsFixed(8)}°'),
                      const SizedBox(height: 8),
                      _buildDataRow('Longitude', '${_currentLocation!.longitude.toStringAsFixed(8)}°'),
                      
                      if (_currentLocation!.altitude != null) ...[
                        const SizedBox(height: 8),
                        _buildDataRow('Altitude', '${_currentLocation!.altitude!.toStringAsFixed(2)} m'),
                      ],
                      
                      if (_currentLocation!.accuracy != null) ...[
                        const SizedBox(height: 8),
                        _buildDataRow('Accuracy', '±${_currentLocation!.accuracy!.toStringAsFixed(2)} m'),
                      ],
                      
                      if (_satelliteCount != null) ...[
                        const SizedBox(height: 8),
                        _buildDataRow('Satellites', _satelliteCount!),
                      ],
                      
                      // Quality Check
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _checkFixQuality()
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _checkFixQuality() ? Colors.green : Colors.orange,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _checkFixQuality() ? Icons.check_circle : Icons.warning,
                              color: _checkFixQuality() ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _checkFixQuality()
                                    ? 'Position meets quality requirements'
                                    : 'Position quality below requirements',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _checkFixQuality() ? Colors.green[800] : Colors.orange[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProviderCard({
    required LocationProvider provider,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedProvider == provider;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.blue.withOpacity(0.1) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedProvider = provider;
          });
          // Reset connection if switching FROM emlid TO phone
          if (provider == LocationProvider.phone && _isConnected) {
            await _disconnectFromEmlid();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.grey[700],
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.blue : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.blue,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
  
  String _formatTimeSince(DateTime time) {
    final duration = DateTime.now().difference(time);
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s ago';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ago';
    } else {
      return '${duration.inHours}h ago';
    }
  }
}
