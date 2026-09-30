import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoform_app/config/api_config.dart';
import '../theme/app_theme.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/notification_event_service.dart';
import '../services/notification_sync_service.dart';
import '../services/app_reset/app_reset_service.dart';
import '../services/app_reset/logout_guard.dart';
import '../services/sync_service.dart';
import '../services/firebase_messaging_service.dart';
import '../widgets/connectivity/connectivity_indicator.dart';
import 'auth/login_screen.dart';
import 'project/projects_screen.dart';
import 'analysis/analysis_types_screen.dart';
import 'basemap/basemap_management_screen.dart';
import 'settings/settings_screen.dart';
import 'profile/profile_screen.dart';
import 'notifications/notifications_screen.dart';
import 'location/location_provider_screen.dart';
import 'layers/layers_screen.dart';
import 'navigation/navigation_screen.dart';
import '../utils/page_routes.dart';
import 'dart:async';

import '../utils/app_logger.dart';
import '../utils/ui_feedback.dart';
import '../widgets/backup/backup_actions.dart';
import '../widgets/sync/sync_result_dialog.dart';
import '../widgets/home/home_menu.dart';
import '../widgets/home/home_status_section.dart';
import '../services/auto_sync_service.dart';
import 'project/project_detail_screen.dart';
import 'readiness/field_readiness_screen.dart';
class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  final ConnectivityService _connectivityService = ConnectivityService();
  final DatabaseService _databaseService = DatabaseService();
  final NotificationEventService _notificationEventService = NotificationEventService();
  final NotificationSyncService _notificationSyncService = NotificationSyncService();
  final FirebaseMessagingService _firebaseMessagingService = FirebaseMessagingService();
  final AuthService _authService = AuthService();
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<NotificationEvent>? _notificationSubscription;
  int _unreadNotificationCount = 0;
  User? _currentUser;
  final GlobalKey<HomeStatusSectionState> _statusKey =
      GlobalKey<HomeStatusSectionState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
    _loadUnreadNotificationCount();
    _syncNotifications();
    _listenToNotificationEvents();
    _setupFirebaseMessagingCallback();
    _loadCurrentUser();
    // Auto-sync (bila diaktifkan di Settings) selama user login.
    AutoSyncService.instance.start();
  }

  /// Buka layar lalu segarkan kartu status saat kembali ke beranda.
  Future<void> _open(Widget screen) async {
    await Navigator.push(context, SmoothPageRoute(builder: (_) => screen));
    if (mounted) _statusKey.currentState?.refresh();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.getUser();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      logWarn('⚠️ Could not load current user: $e', tag: 'UI');
    }
  }

  /// Greeting berdasarkan jam lokal
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Nama tampilan: prioritas fullName, fallback ke username
  String get _displayName {
    if (_currentUser == null) return '';
    final name = _currentUser!.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      // Ambil nama pertama saja supaya tidak terlalu panjang
      return name.split(' ').first;
    }
    return _currentUser!.username;
  }

  /// Inisial untuk avatar (maks 2 karakter)
  String get _initials {
    if (_currentUser == null) return '?';
    final name = _currentUser!.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0][0].toUpperCase();
    }
    return _currentUser!.username[0].toUpperCase();
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
      logWarn('Error loading unread notification count: $e', tag: 'UI');
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
    
    // Reload notification count + tarik inbox server saat app kembali foreground
    // (menambal push yang tertunda Doze).
    if (state == AppLifecycleState.resumed) {
      _loadUnreadNotificationCount();
      _syncNotifications();
      _statusKey.currentState?.refresh();
    }
  }

  /// Tarik inbox server (best-effort); refresh badge bila ada yang baru.
  Future<void> _syncNotifications() async {
    final added = await _notificationSyncService.sync();
    if (added > 0 && mounted) _loadUnreadNotificationCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _firebaseMessagingService.onNewNotificationCallback = null;
    AutoSyncService.instance.stop();
    _connectivitySubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Terestria', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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
              HapticFeedback.selectionClick();
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
            // Premium Header — personalized greeting
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            decoration: const BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Greeting + name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _displayName.isNotEmpty ? _displayName : 'Terestria',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Agricultural & Environmental Mapping',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Avatar inisial
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Status lapangan + menu berkelompok (beranda = dasbor lapangan).
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: () async => _statusKey.currentState?.refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  HomeStatusSection(
                    key: _statusKey,
                    onOpenProject: (project) => _open(
                        ProjectDetailScreen(project: project)),
                    onOpenReadiness: () =>
                        _open(const FieldReadinessScreen()),
                  ),
                  const HomeSectionLabel('Survey'),
                  HomeMenuGrid(children: [
                    HomeMenuCard(
                      icon: Icons.folder_rounded,
                      title: 'Projects',
                      description: 'Collect & manage data',
                      color: AppTheme.primaryGreen,
                      onTap: () => _open(const ProjectsScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.layers_rounded,
                      title: 'Layers',
                      description: 'Overlays',
                      color: AppTheme.darkGreen,
                      onTap: () => _open(const LayersScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.map_rounded,
                      title: 'Basemaps',
                      description: 'Offline maps',
                      color: AppTheme.accentGreen,
                      onTap: () => _open(const BasemapManagementScreen()),
                    ),
                  ]),
                  const HomeSectionLabel('Tools'),
                  HomeMenuGrid(children: [
                    HomeMenuCard(
                      icon: Icons.navigation_rounded,
                      title: 'Navigation',
                      description: 'Route & navigate',
                      color: AppTheme.primaryGreen,
                      onTap: () => _open(const NavigationScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.analytics_rounded,
                      title: 'Analysis',
                      description: 'Reports',
                      color: AppTheme.primaryBlue,
                      onTap: () => _open(const AnalysisTypesScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.fact_check_rounded,
                      title: 'Readiness',
                      description: 'Pre-field check',
                      color: Colors.orange.shade800,
                      onTap: () => _open(const FieldReadinessScreen()),
                    ),
                  ]),
                  const HomeSectionLabel('Account & device'),
                  HomeMenuGrid(children: [
                    HomeMenuCard(
                      icon: Icons.notifications_rounded,
                      title: 'Notifications',
                      description: 'Updates',
                      color: AppTheme.primaryGreen,
                      badge: _unreadNotificationCount > 0
                          ? _unreadNotificationCount
                          : null,
                      onTap: () async {
                        await _open(const NotificationsScreen());
                        _loadUnreadNotificationCount();
                      },
                    ),
                    HomeMenuCard(
                      icon: Icons.satellite_alt_rounded,
                      title: 'Location',
                      description: 'GPS provider',
                      color: AppTheme.darkGreen,
                      onTap: () => _open(const LocationProviderScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      description: 'Preferences',
                      color: AppTheme.accentGreen,
                      onTap: () => _open(const SettingsScreen()),
                    ),
                    HomeMenuCard(
                      icon: Icons.person_rounded,
                      title: 'Profile',
                      description: 'Account',
                      color: AppTheme.primaryGreen,
                      onTap: () => _open(const ProfileScreen()),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
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

  /// Logout = reset app ke kondisi awal. Bila masih ada data belum
  /// tersinkron / sesi tracking, user diberi pilihan Save backup / Sync first
  /// / Cancel / Delete & log out (ketik DELETE).
  void _logout(BuildContext context) async {
    var confirm = false;
    while (!confirm) {
      final PendingLogoutData pending;
      try {
        pending = await countPendingLogoutData();
      } catch (e, st) {
        // Tak bisa memastikan data aman → jangan lanjut logout.
        if (context.mounted) {
          showErrorFeedback(context,
              'Could not check for unsynced data, so logout was stopped',
              error: e, stack: st, tag: 'AUTH');
        }
        return;
      }
      logInfo('Logout requested; pending: $pending', tag: 'AUTH');
      if (!context.mounted) return;
      final choice = await showLogoutGuardDialog(context, pending);
      if (!context.mounted) return;
      switch (choice) {
        case LogoutChoice.cancel:
          return;
        case LogoutChoice.sync:
          await _syncBeforeLogout(context);
          if (!context.mounted) return;
        case LogoutChoice.backup:
          await createAndShareBackup(context);
          if (!context.mounted) return;
        case LogoutChoice.wipe:
          if (!pending.isEmpty) {
            logWarn('Forced logout with pending data: $pending', tag: 'AUTH');
          }
          confirm = true;
      }
    }

    // Reset app ke kondisi awal (hapus data user ini) lalu ke layar login.
    _showBlockingProgress(context, 'Logging out and clearing this phone…');
    // Jangan menghapus DB saat sync masih menulis: hentikan auto-sync dan
    // tunggu sync yang sedang berjalan (maks 30 dtk).
    AutoSyncService.instance.stop();
    try {
      await SyncService()
          .runExclusive(() async {})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      logWarn('Logout: a sync was still running after 30 s ($e)', tag: 'AUTH');
    }
    final report = await AppResetService().reset();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(report.success
          ? 'Logged out — data on this phone was cleared'
          : 'Logged out, but some data could not be cleared '
              '(${report.failed.keys.join(', ')})'),
    ));
  }

  /// Dialog progres yang tak bisa ditutup user (tutup lewat rootNavigator).
  void _showBlockingProgress(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ]),
        ),
      ),
    );
  }

  /// Jalankan sync semua data tertunda dengan dialog progres, lalu kembali ke
  /// dialog logout (jumlah dihitung ulang).
  Future<void> _syncBeforeLogout(BuildContext context) async {
    _showBlockingProgress(context, 'Syncing data…');
    FullSyncResult? result;
    String? failure;
    try {
      result = await SyncService().syncAllUnsyncedData();
    } catch (e, st) {
      logError('Sync before logout failed', tag: 'AUTH', error: e, stack: st);
      failure = 'Sync failed. ${friendlyErrorMessage(e)}';
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (result != null) {
      // Gagal sebagian → dialog berisi alasannya, lalu kembali ke dialog
      // logout dengan jumlah terbaru.
      await showFullSyncResult(context, result);
    } else {
      showInfoFeedback(context, failure!, warning: true,
          duration: const Duration(seconds: 5));
    }
  }
}
