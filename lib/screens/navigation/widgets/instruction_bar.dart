import 'package:flutter/material.dart';
import '../../../models/route_result.dart';
import '../../../theme/app_theme.dart';

/// Top banner shown while navigation is active.
///
/// Google-style turn-by-turn: it shows the UPCOMING maneuver with a distance
/// count-down (so the prompt appears BEFORE the turn), plus a secondary
/// "then …" preview of the maneuver after it.
class InstructionBar extends StatelessWidget {
  /// The maneuver coming up next (ahead of the current position).
  final RouteInstruction? instruction;

  /// Distance in meters from current position to [instruction].
  final double distanceToNext;

  /// The maneuver after [instruction] — shown as a small "then" preview.
  final RouteInstruction? following;

  final bool isOffRoute;

  const InstructionBar({
    super.key,
    required this.instruction,
    required this.distanceToNext,
    this.following,
    this.isOffRoute = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isOffRoute) {
      return _Banner(
        icon: Icons.refresh_rounded,
        color: Colors.orange.shade800,
        action: 'Keluar jalur',
        street: 'Menghitung ulang rute…',
        distStr: '',
        following: null,
      );
    }

    final instr = instruction;
    if (instr == null) return const SizedBox.shrink();

    return _Banner(
      icon: _signIcon(instr.sign),
      color: _phaseColor(distanceToNext),
      action: instr.directionLabel,
      street: instr.streetName,
      distStr: _formatDistance(distanceToNext),
      following: following,
    );
  }

  // Closer to the maneuver → warmer/urgent color.
  Color _phaseColor(double meters) {
    if (meters > 0 && meters <= 40) return AppTheme.darkGreen;
    return AppTheme.primaryGreen;
  }

  String _formatDistance(double meters) {
    if (meters <= 0) return 'Sekarang';
    if (meters <= 30) return 'Sekarang';
    if (meters < 1000) {
      // Round to a friendly step (10 m) like turn-by-turn apps.
      final rounded = (meters / 10).round() * 10;
      return '$rounded m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static IconData _signIcon(int sign) {
    switch (sign) {
      case TurnSign.uTurn:            return Icons.u_turn_left_rounded;
      case TurnSign.keepLeft:         return Icons.turn_slight_left_rounded;
      case TurnSign.turnSharpLeft:    return Icons.turn_sharp_left_rounded;
      case TurnSign.turnLeft:         return Icons.turn_left_rounded;
      case TurnSign.turnSlightLeft:   return Icons.turn_slight_left_rounded;
      case TurnSign.continueOnStreet: return Icons.straight_rounded;
      case TurnSign.turnSlightRight:  return Icons.turn_slight_right_rounded;
      case TurnSign.turnRight:        return Icons.turn_right_rounded;
      case TurnSign.turnSharpRight:   return Icons.turn_sharp_right_rounded;
      case TurnSign.finish:           return Icons.flag_rounded;
      case TurnSign.keepRight:        return Icons.turn_slight_right_rounded;
      default:                        return Icons.navigation_rounded;
    }
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String action;
  final String street;
  final String distStr;
  final RouteInstruction? following;

  const _Banner({
    required this.icon,
    required this.color,
    required this.action,
    required this.street,
    required this.distStr,
    required this.following,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Primary row: maneuver + distance ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (distStr.isNotEmpty)
                        Text(
                          distStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            letterSpacing: 0.2,
                          ),
                        ),
                      Text(
                        street.isNotEmpty ? '$action • $street' : action,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Secondary row: "then …" preview ──
          if (following != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 7, 16, 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Lalu',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    InstructionBar._signIcon(following!.sign),
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      following!.streetName.isNotEmpty
                          ? '${following!.directionLabel} • ${following!.streetName}'
                          : following!.directionLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
