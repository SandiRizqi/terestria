import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class DirectionBeamPainter extends CustomPainter {
  final Color color;
  
  DirectionBeamPainter({required this.color});
  
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
        color.withOpacity(0.7), // Warna dengan opacity di tengah
        color.withOpacity(0.4), // Lebih tipis
        color.withOpacity(0.0), // Transparan di ujung
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
  final bool isEmlidGPS;

  const UserLocationMarker({
    Key? key,
    required this.bearing,
    this.isEmlidGPS = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Warna berbeda untuk Phone GPS (blue) vs Emlid GPS (green/teal)
    final markerColor = isEmlidGPS 
        ? const Color(0xFF00BFA5) // Teal/turquoise untuk Emlid RTK GPS
        : const Color(0xFF4285F4); // Google Maps blue untuk Phone GPS
    
    return Transform.rotate(
      angle: bearing * (math.pi / 180),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Direction beam (cahaya menyorot)
          CustomPaint(
            size: const Size(60, 60),
            painter: DirectionBeamPainter(color: markerColor),
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
          // Colored circle (blue for phone, teal for Emlid)
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: markerColor,
            ),
          ),
          // Small icon indicator for Emlid GPS
          if (isEmlidGPS)
            Positioned(
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.router,
                  size: 8,
                  color: Color(0xFF00BFA5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
