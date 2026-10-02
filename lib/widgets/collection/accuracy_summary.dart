import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../services/project_rules.dart';

/// Akurasi record dibanding batas project (SPEC §3.6). Melebihi batas →
/// peringatan; simpan tetap boleh (server yang menolak push-nya). Tidak
/// tampil bila project tanpa batas atau record tanpa titik GPS.
class AccuracySummary extends StatelessWidget {
  final GeometryType geometryType;
  final List<GeoPoint> points;
  final double? limit;

  const AccuracySummary({
    super.key,
    required this.geometryType,
    required this.points,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final info = accuracySummary(geometryType, points, limit);
    if (info == null) return const SizedBox.shrink();
    final color = info.over ? Colors.red.shade700 : Colors.green.shade700;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(info.over ? Icons.warning_amber_rounded : Icons.gps_fixed,
              color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.text,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                if (info.over) ...[
                  const SizedBox(height: 2),
                  Text(
                    geometryType == GeometryType.point
                        ? 'The server will reject this record. Take the point '
                            'again with a better GPS fix.'
                        : 'You can still save, but the server will reject this '
                            'record until the inaccurate points are removed.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
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
