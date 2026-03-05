import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_token_service.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FCMTokenService _fcmTokenService = FCMTokenService();
  
  User? _user;
  String? _fcmToken;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get user data
      final user = await _authService.getUser();
      
      // Get FCM token if available
      String? fcmToken = _fcmTokenService.lastRegisteredToken;
      
      setState(() {
        _user = user;
        _fcmToken = fcmToken;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        elevation: 0,
        backgroundColor: AppTheme.primaryGreen,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? const Center(
                  child: Text(
                    'No user data available',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUserData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Profile Header
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Column(
                              children: [
                                const SizedBox(height: 24),
                                // Avatar
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    child: Text(
                                      _user!.username.isNotEmpty
                                          ? _user!.username[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Username
                                Text(
                                  _user!.username,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_user!.fullName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _user!.fullName!,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        
                        // Profile Details
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Account Information Section
                              _buildSectionTitle('Account Information'),
                              const SizedBox(height: 12),
                              
                              _buildInfoCard(
                                icon: Icons.person_outline,
                                label: 'Username',
                                value: _user!.username,
                                onCopy: () => _copyToClipboard(_user!.username, 'Username'),
                              ),
                              
                              if (_user!.email != null)
                                _buildInfoCard(
                                  icon: Icons.email_outlined,
                                  label: 'Email',
                                  value: _user!.email!,
                                  onCopy: () => _copyToClipboard(_user!.email!, 'Email'),
                                ),

                              if (_user!.token != null) ...[
                                const SizedBox(height: 24),
                                _buildSectionTitle('Authentication'),
                                const SizedBox(height: 12),
                                
                                _buildInfoCard(
                                  icon: Icons.key_outlined,
                                  label: 'User Token',
                                  value: _maskToken(_user!.token!),
                                  onCopy: () => _copyToClipboard(_user!.token!, 'User Token'),
                                  isSecret: true,
                                ),
                              ],
                              
                              const SizedBox(height: 24),
                              _buildSectionTitle('Notifications'),
                              const SizedBox(height: 12),
                              
                              _buildInfoCard(
                                icon: Icons.notifications_outlined,
                                label: 'Device Token',
                                value: _fcmToken != null ? _maskToken(_fcmToken!) : '-',
                                onCopy: _fcmToken != null ? () => _copyToClipboard(_fcmToken!, 'Device Token') : null,
                                isSecret: _fcmToken != null,
                                status: _fcmToken != null ? 'Active' : null,
                                statusColor: _fcmToken != null ? Colors.green : null,
                              ),
                              
                             

                              
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onCopy,
    bool isSecret = false,
    String? status,
    Color? statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.getCardDecoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          onTap: onCopy != null ? () {} : null, // Ripple effect base

          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: AppTheme.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor?.withOpacity(0.1) ?? Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: statusColor ?? Colors.grey,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor ?? Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: AppTheme.textSecondary,
                    onPressed: onCopy,
                    tooltip: 'Copy',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _maskToken(String token) {
    if (token.length <= 8) return token;
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }
}
