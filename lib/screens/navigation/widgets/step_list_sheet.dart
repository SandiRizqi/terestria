import 'package:flutter/material.dart';
import '../../../models/route_result.dart';
import '../../../theme/app_theme.dart';

/// Maps a GraphHopper turn sign to a Material direction icon.
IconData maneuverIcon(int sign) {
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

/// Opens a Google-style per-segment directions list for the given route.
Future<void> showStepListSheet(
  BuildContext context, {
  required RouteResult route,
  int currentSegment = 0,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StepListSheet(route: route, currentSegment: currentSegment),
  );
}

class _StepListSheet extends StatelessWidget {
  final RouteResult route;
  final int currentSegment;

  const _StepListSheet({required this.route, required this.currentSegment});

  @override
  Widget build(BuildContext context) {
    final instructions = route.instructions;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt_rounded,
                        color: AppTheme.primaryGreen, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Directions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${route.formattedDistance} • ${route.formattedTime}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Steps
              Expanded(
                child: instructions.isEmpty
                    ? const Center(
                        child: Text(
                          'No directions for this route',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: instructions.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, i) {
                          final step = instructions[i];
                          final isDone = step.interval <= currentSegment;
                          final isCurrent = i + 1 < instructions.length
                              ? (step.interval <= currentSegment &&
                                  instructions[i + 1].interval > currentSegment)
                              : step.interval <= currentSegment;
                          return _StepTile(
                            step: step,
                            index: i,
                            isDone: isDone && !isCurrent,
                            isCurrent: isCurrent,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepTile extends StatelessWidget {
  final RouteInstruction step;
  final int index;
  final bool isDone;
  final bool isCurrent;

  const _StepTile({
    required this.step,
    required this.index,
    required this.isDone,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCurrent
        ? AppTheme.primaryGreen
        : isDone
            ? Colors.grey.shade400
            : AppTheme.textPrimary;

    return Container(
      color: isCurrent
          ? AppTheme.primaryGreen.withValues(alpha: 0.06)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppTheme.primaryGreen.withValues(alpha: 0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(maneuverIcon(step.sign), color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.streetName.isNotEmpty
                      ? '${step.directionLabel} • ${step.streetName}'
                      : step.directionLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                    decoration:
                        isDone ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                if (step.distance > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.formattedDistance,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
