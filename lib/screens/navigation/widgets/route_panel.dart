import 'package:flutter/material.dart';
import '../../../models/project_model.dart';
import '../../../models/route_result.dart';
import '../../../theme/app_theme.dart';

/// Collapsible bottom panel shown during / before navigation.
class RoutePanel extends StatelessWidget {
  // Project selector
  final List<Project> projects;
  final Project? selectedProject;
  final ValueChanged<Project?> onProjectChanged;

  // Route info
  final RouteResult? routeResult;
  final int currentSegment;
  final double? gpsAccuracy;

  // Navigation state
  final bool isNavigating;
  final bool isCalculating;
  final bool isInitializingRouter; // true while GraphHopper builds graph
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;
  final VoidCallback onChooseBasemap;
  final VoidCallback onClearRoute;

  const RoutePanel({
    super.key,
    required this.projects,
    required this.selectedProject,
    required this.onProjectChanged,
    required this.routeResult,
    required this.currentSegment,
    required this.gpsAccuracy,
    required this.isNavigating,
    required this.isCalculating,
    this.isInitializingRouter = false,
    required this.onStartNavigation,
    required this.onStopNavigation,
    required this.onChooseBasemap,
    required this.onClearRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Project selector ──────────────────────────────────────
                _buildProjectSelector(context),
                const SizedBox(height: 12),

                // ── Route info ────────────────────────────────────────────
                if (isInitializingRouter)
                  const _LoadingRow(
                    label: 'Preparing routing engine...',
                    sublabel: 'First run may take a few seconds',
                  )
                else if (isCalculating)
                  const _LoadingRow(label: 'Calculating route...')
                else if (routeResult != null)
                  _buildRouteInfo()
                else
                  _buildNoRouteHint(),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Action buttons ────────────────────────────────────────
                _buildActions(context),
              ],
            ),
          ),
        ],
    );
  }

  // ── Project selector ────────────────────────────────────────────────────────

  Widget _buildProjectSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Show Project Data',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Project?>(
              isExpanded: true,
              value: selectedProject,
              hint: const Text('— None —', style: TextStyle(fontSize: 13)),
              items: [
                const DropdownMenuItem<Project?>(
                  value: null,
                  child: Text('— None —', style: TextStyle(fontSize: 13)),
                ),
                ...projects.map((p) => DropdownMenuItem<Project?>(
                      value: p,
                      child: Text(
                        p.name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: onProjectChanged,
            ),
          ),
        ),
      ],
    );
  }

  // ── Route info ──────────────────────────────────────────────────────────────

  Widget _buildRouteInfo() {
    final route     = routeResult!;
    final remaining = route.remainingDistance(currentSegment);
    final distStr   = remaining < 1000
        ? '${remaining.toStringAsFixed(0)} m'
        : '${(remaining / 1000).toStringAsFixed(1)} km';

    // Estimate remaining time proportionally
    final ratio     = route.distance > 0 ? remaining / route.distance : 0.0;
    final remMs     = (route.time * ratio).toInt();
    final remMin    = remMs ~/ 60000;
    final timeStr   = remMin < 60 ? '$remMin min' : '${remMin ~/ 60}h ${remMin % 60}m';

    final accStr = gpsAccuracy != null
        ? '${gpsAccuracy!.toStringAsFixed(1)} m'
        : '—';

    return Column(
      children: [
        Row(
          children: [
            _InfoChip(
              icon:  Icons.route_rounded,
              label: 'Remaining',
              value: distStr,
              color: AppTheme.primaryGreen,
            ),
            const SizedBox(width: 10),
            _InfoChip(
              icon:  Icons.access_time_rounded,
              label: 'ETA',
              value: timeStr,
              color: AppTheme.darkGreen,
            ),
            const SizedBox(width: 10),
            _InfoChip(
              icon:  Icons.gps_fixed_rounded,
              label: 'GPS Accuracy',
              value: accStr,
              color: AppTheme.accentGreen,
            ),
          ],
        ),
        if (isNavigating)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:  Colors.green.shade500,
                    shape:  BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Navigating — Total route ${route.formattedDistance}',
                  style: TextStyle(
                    fontSize: 11,
                    color:    Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNoRouteHint() {
    return Row(
      children: [
        Icon(Icons.touch_app_rounded, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Long-press the map to create a route',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  // ── Action buttons ──────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        // Start / Stop navigation
        Expanded(
          child: isNavigating
              ? ElevatedButton.icon(
                  onPressed: onStopNavigation,
                  icon:  const Icon(Icons.stop_circle_rounded, size: 18),
                  label: const Text('Stop', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )
              : ElevatedButton.icon(
                  // Disabled while router is initializing OR no route yet
                  onPressed: (!isInitializingRouter && routeResult != null)
                      ? onStartNavigation
                      : null,
                  icon:  const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Start Navigation', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        // Basemap
        _IconBtn(
          icon:    Icons.map_rounded,
          tooltip: 'Change Basemap',
          onTap:   onChooseBasemap,
        ),
        const SizedBox(width: 8),
        // Clear route
        if (routeResult != null)
          _IconBtn(
            icon:    Icons.clear_rounded,
            tooltip: 'Clear Route',
            color:   Colors.red.shade400,
            onTap:   onClearRoute,
          ),
      ],
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData  icon;
  final String    tooltip;
  final VoidCallback onTap;
  final Color     color;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = AppTheme.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color:        color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap:        onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:   Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String  label;
  final String? sublabel;
  const _LoadingRow({required this.label, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(
          width:  16,
          height: 16,
          child:  CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
