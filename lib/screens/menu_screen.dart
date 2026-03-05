import 'package:flutter/material.dart';
import 'package:geoform_app/config/api_config.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/notification_event_service.dart';
import '../services/firebase_messaging_service.dart';
import '../widgets/connectivity/connectivity_indicator.dart';
import 'auth/login_screen.dart';
import 'project/projects_screen.dart';
import 'basemap/basemap_management_screen.dart';
import 'settings/settings_screen.dart';
import 'profile/profile_screen.dart';
import 'notifications/notifications_screen.dart';
import 'location/location_provider_screen.dart';
import 'layers/layers_screen.dart';
import 'dart:async';

class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  final ConnectivityService _connectivityService = ConnectivityService();
  final DatabaseService _databaseService = DatabaseService();
  final NotificationEventService _notificationEventService = NotificationEventService();
  final FirebaseMessagingService _firebaseMessagingService = FirebaseMessagingService();
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<NotificationEvent>? _notificationSubscription;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
    _loadUnreadNotificationCount();
    _listenToNotificationEvents();
    _setupFirebaseMessagingCallback();
  }

  void _initConnectivity() {
    _connectivityService.startMonitoring();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final count = await _databaseService.getUnreadNotificationCount();
      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
      }
    } catch (e) {
      print('Error loading unread notification count: $e');
    }
  }

  void _listenToNotificationEvents() {
    _notificationSubscription = _notificationEventService.notificationStream.listen((event) {
      // Reload unread count whenever notification event occurs
      _loadUnreadNotificationCount();
    });
  }

  void _setupFirebaseMessagingCallback() {
    // Set callback untuk immediate update saat notifikasi masuk di foreground
    _firebaseMessagingService.onNewNotificationCallback = () {
      if (mounted) {
        _loadUnreadNotificationCount();
      }
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Reload notification count when app comes to foreground
    if (state == AppLifecycleState.resumed) {
      _loadUnreadNotificationCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _firebaseMessagingService.onNewNotificationCallback = null;
    _connectivitySubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text('Terestria ${ApiConfig.appVersion}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: AppTheme.primaryGreen,
        actions: [
          const ConnectivityIndicator(
            showLabel: true,
            iconSize: 16,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 12,
            offset: const Offset(0, 50),
            onSelected: (value) async {
              if (value == 'about') {
                _showAboutDialog(context);
              } else if (value == 'logout') {
                _logout(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About App',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Version & Info',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Logout',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.red,
                            ),
                          ),
                          Text(
                            'Sign out of account',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Premium Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            decoration: const BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Terestria',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Agricultural & Environmental Data Collection',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Menu Grid
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.9,
              children: [
                _buildMenuCard(
                  context,
                  icon: Icons.folder_rounded,
                  title: 'Projects',
                  description: 'Manage data',
                  color: AppTheme.primaryGreen,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProjectsScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuCard(
                  context,
                  icon: Icons.layers_rounded,
                  title: 'Layers',
                  description: 'Manage overlays',
                  color: Colors.teal.shade600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LayersScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuCard(
                  context,
                  icon: Icons.map_rounded,
                  title: 'Basemaps',
                  description: 'Custom basemaps',
                  color: Colors.blue.shade600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BasemapManagementScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuCard(
                  context,
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  description: 'Stay updated',
                  color: Colors.deepOrange.shade500,
                  badge: _unreadNotificationCount > 0 ? _unreadNotificationCount : null,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsScreen(),
                      ),
                    );
                    _loadUnreadNotificationCount();
                  },
                ),
                _buildMenuCard(
                  context,
                  icon: Icons.satellite_alt_rounded,
                  title: 'Location',
                  description: 'GPS Provider',
                  color: Colors.indigo.shade500,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LocationProviderScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuCard(
                  context,
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  description: 'Preferences',
                  color: Colors.blueGrey.shade600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                // (Profile could go here if needed as an extra item, but generally Settings is enough.
                // We will leave Profile in the grid to preserve full functionality.)
                _buildMenuCard(
                  context,
                  icon: Icons.person_rounded,
                  title: 'Profile',
                  description: 'Account info',
                  color: Colors.deepPurple.shade500,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Container(
      decoration: AppTheme.getCardDecoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: color.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 32,
                        color: color,
                      ),
                    ),
                    if (badge != null && badge > 0)
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            badge > 99 ? '99+' : badge.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.eco, size: 32, color: Colors.green),
              SizedBox(width: 12),
              Text('Terestria'),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${ApiConfig.appVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Agricultural and Environmental Mapping App',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'A professional geospatial data collection platform designed for agricultural and environmental field surveys.',
                ),
                SizedBox(height: 12),
                Text(
                  'Key Features:\n'
                  '• Custom survey forms\n'
                  '• Point, Line & Polygon mapping\n'
                  '• Real-time GPS tracking\n'
                  '• Offline functionality\n'
                  '• Multiple basemap support\n'
                  '• Data export capabilities',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  void _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final authService = AuthService();
        await authService.logout();
        
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logged out successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error during logout: $e')),
          );
        }
      }
    }
  }
}
