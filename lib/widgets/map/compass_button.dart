import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Normalisasi sudut derajat ke rentang (-180, 180].
/// Dipakai untuk memutar peta via jalur terpendek (shortest-arc).
double normalizeDegrees(double deg) {
  final m = ((deg + 180) % 360 + 360) % 360 - 180;
  return m == -180 ? 180 : m;
}

/// Selisih sudut terpendek dari [from] ke [to] (hasil di (-180, 180]).
double shortestDelta(double from, double to) => normalizeDegrees(to - from);

/// Tombol kompas penunjuk utara untuk peta flutter_map.
///
/// Jarum diikat ke **rotasi peta** ([MapController.camera.rotation]) — bukan
/// heading magnetometer — sehingga selalu menunjuk utara peta. Perubahan rotasi
/// (gesture maupun programatik) dipantau via [MapController.mapEventStream].
/// Tap → peta beranimasi mulus ke north-up (tween shortest-arc, easeOut).
class CompassButton extends StatefulWidget {
  final MapController mapController;
  final double size;
  final Duration resetDuration;

  /// Dipanggil saat tombol ditekan (mis. untuk mematikan mode heading-up).
  final VoidCallback? onResetToNorth;

  const CompassButton({
    super.key,
    required this.mapController,
    this.size = 40,
    this.resetDuration = const Duration(milliseconds: 300),
    this.onResetToNorth,
  });

  @override
  State<CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<CompassButton>
    with SingleTickerProviderStateMixin {
  double _rotation = 0; // derajat rotasi peta terkini
  double _animFrom = 0;
  StreamSubscription<MapEvent>? _sub;
  late final AnimationController _resetCtrl;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(vsync: this, duration: widget.resetDuration)
      ..addListener(() {
        final t = Curves.easeOut.transform(_resetCtrl.value);
        final angle = _animFrom * (1 - t); // menuju 0
        try {
          widget.mapController.rotate(angle);
        } catch (_) {}
      });

    _sub = widget.mapController.mapEventStream.listen((_) {
      double r;
      try {
        r = widget.mapController.camera.rotation;
      } catch (_) {
        return;
      }
      if (r != _rotation && mounted) setState(() => _rotation = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resetCtrl.dispose();
    super.dispose();
  }

  void _animateToNorth() {
    double cur;
    try {
      cur = normalizeDegrees(widget.mapController.camera.rotation);
    } catch (_) {
      return;
    }
    if (cur == 0) return;
    _animFrom = cur;
    _resetCtrl
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onResetToNorth?.call();
        _animateToNorth();
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Transform.rotate(
          angle: -_rotation * (math.pi / 180),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: CompassPainter(),
          ),
        ),
      ),
    );
  }
}

/// Painter jarum kompas: utara (merah) / selatan (abu) + label N.
class CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final northPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - r * 0.68)
        ..lineTo(cx - r * 0.18, cy)
        ..lineTo(cx, cy - r * 0.12)
        ..lineTo(cx + r * 0.18, cy)
        ..close(),
      northPaint,
    );

    final southPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy + r * 0.68)
        ..lineTo(cx - r * 0.18, cy)
        ..lineTo(cx, cy + r * 0.12)
        ..lineTo(cx + r * 0.18, cy)
        ..close(),
      southPaint,
    );

    canvas.drawCircle(Offset(cx, cy), r * 0.12, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.12,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final tp = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - r * 0.68 - tp.height - 1));
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) => false;
}
