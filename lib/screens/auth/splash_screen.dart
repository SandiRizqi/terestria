import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../services/scope_topic_service.dart';
import '../auth/login_screen.dart';
import '../menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Fade: mulai dari 0 → 1, curve easeOut
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Scale: logo muncul dari 0.75 → 1.0 dengan bouncy feel
    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // Slide teks dari bawah sedikit ke posisi normal
    _slideAnimation = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
    _checkAuth();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    // Wait for animation
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final isLoggedIn = await _authService.isLoggedIn();

    if (mounted) {
      if (isLoggedIn) {
        // Verify token
        final isValid = await _authService.verifyToken();
        if (!isValid) {
          // Token invalid, go to login
          _navigateToLogin();
          return;
        }

        // Re-sync FCM topic subscriptions saat app kembali dibuka —
        // fire-and-forget di background agar tidak menahan navigasi ke home.
        try {
          final user = await _authService.getUser();
          ScopeTopicService().syncTopicsInBackground(user?.scope ?? []);
        } catch (e) {
          print('⚠️ [Splash] FCM topic sync failed: $e');
        }

        // Go to home
        _navigateToHome();
      } else {
        // Not logged in, go to login
        _navigateToLogin();
      }
    }
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MenuScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.85),
              const Color(0xFF014D25), // tone gelap di bawah
            ],
          ),
        ),
        child: Stack(
          children: [
            // Konten utama — tengah layar
            Center(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo dengan shadow premium
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                  spreadRadius: -4,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/terestria_logo_square-removebg-preview.png',
                              width: 120,
                              height: 120,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.eco_rounded,
                                    size: 60,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Teks slide dari bawah
                          Transform.translate(
                            offset: Offset(0, _slideAnimation.value),
                            child: Column(
                              children: [
                                const Text(
                                  'Terestria',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Agricultural & Environmental Mapping',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.75),
                                    letterSpacing: 0.3,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Loading dots di bagian bawah layar
            Positioned(
              bottom: 56,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: const _LoadingDots(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiga titik animasi loading yang lebih elegan dari CircularProgressIndicator.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // Setiap dot punya delay berbeda (offset 0.0, 0.2, 0.4)
            final delay = i * 0.25;
            final t = (((_ctrl.value - delay) % 1.0 + 1.0) % 1.0);
            final opacity = (t < 0.5) ? t * 2 : (1.0 - t) * 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
