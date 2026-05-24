import 'package:flutter/material.dart';
import '../../../models/route_result.dart';
import '../../../theme/app_theme.dart';

/// Top bar shown while navigation is active.
/// Displays current turn instruction + distance to next maneuver.
class InstructionBar extends StatelessWidget {
  final RouteInstruction? instruction;
  final double distanceToNext; // meters
  final bool isOffRoute;

  const InstructionBar({
    super.key,
    required this.instruction,
    required this.distanceToNext,
    this.isOffRoute = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isOffRoute) {
      return _buildBar(
        context,
        icon:    Icons.refresh_rounded,
        color:   Colors.orange.shade700,
        label:   'Off route — Recalculating...',
        distStr: '',
      );
    }

    final instr = instruction;
    if (instr == null) return const SizedBox.shrink();

    return _buildBar(
      context,
      icon:    _signIcon(instr.sign),
      color:   AppTheme.primaryGreen,
      label:   instr.directionLabel,
      distStr: _formatDistance(distanceToNext),
    );
  }

  Widget _buildBar(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String distStr,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color:       Colors.white,
                fontSize:    15,
                fontWeight:  FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (distStr.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              distStr,
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters <= 0) return '';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  IconData _signIcon(int sign) {
    switch (sign) {
      case TurnSign.uTurn:             return Icons.u_turn_left_rounded;
      case TurnSign.keepLeft:          return Icons.turn_slight_left_rounded;
      case TurnSign.turnSharpLeft:     return Icons.turn_sharp_left_rounded;
      case TurnSign.turnLeft:          return Icons.turn_left_rounded;
      case TurnSign.turnSlightLeft:    return Icons.turn_slight_left_rounded;
      case TurnSign.continueOnStreet:  return Icons.straight_rounded;
      case TurnSign.turnSlightRight:   return Icons.turn_slight_right_rounded;
      case TurnSign.turnRight:         return Icons.turn_right_rounded;
      case TurnSign.turnSharpRight:    return Icons.turn_sharp_right_rounded;
      case TurnSign.finish:            return Icons.flag_rounded;
      case TurnSign.keepRight:         return Icons.turn_slight_right_rounded;
      default:                         return Icons.navigation_rounded;
    }
  }
}
