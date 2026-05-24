import 'package:flutter/material.dart';

/// Custom page route dengan animasi fade + slide ke atas yang halus.
/// Dipakai sebagai pengganti MaterialPageRoute di seluruh app.
///
/// Contoh penggunaan:
/// ```dart
/// Navigator.push(context, SmoothPageRoute(builder: (_) => const MyScreen()));
/// ```
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  final Widget Function(BuildContext context) builder;

  SmoothPageRoute({required this.builder})
      : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade
            final fadeAnim = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            );

            // Slide dari bawah sedikit (subtle — hanya 18px)
            final slideAnim = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ));

            return FadeTransition(
              opacity: fadeAnim,
              child: SlideTransition(
                position: slideAnim,
                child: child,
              ),
            );
          },
        );
}
