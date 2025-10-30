import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class DirectionBeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Menggambar cone/beam yang menunjuk ke atas
    final beamPath = ui.Path()
      ..moveTo(center.dx, center.dy) // Titik tengah (posisi user)
      ..lineTo(center.dx - 18, 0) // Kiri atas (lebar beam)
      ..lineTo(center.dx + 18, 0) // Kanan atas (lebar beam)
      ..close();

    // Membuat gradient beam yang menyorot ke atas
    final rect = beamPath.getBounds();
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        const Color(0xFF4285F4).withOpacity(0.7), // Blue dengan opacity di tengah
        const Color(0xFF4285F4).withOpacity(0.4), // Lebih tipis
        const Color(0xFF4285F4).withOpacity(0.0), // Transparan di ujung
      ],
      stops: const [0.0, 0.6, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(beamPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class UserLocationMarker extends StatelessWidget {
  final double bearing;

  const UserLocationMarker({
    Key? key,
    required this.bearing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: bearing * (math.pi / 180),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Direction beam (cahaya menyorot)
          CustomPaint(
            size: const Size(60, 60),
            painter: DirectionBeamPainter(),
          ),
          // White shadow/border circle
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Blue circle
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF4285F4), // Google Maps blue
            ),
          ),
        ],
      ),
    );
  }
}
