import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../models/settings/app_settings.dart';
import '../../utils/record_title.dart';
import '../style/style_editor.dart';
import 'project_feature_layers.dart';

/// Daftar pilihan saat satu tap di peta mengenai beberapa feature
/// (mis. polygon bertumpuk). Mengembalikan record yang dipilih, atau null
/// bila sheet ditutup tanpa memilih.
Future<GeoData?> showFeaturePickSheet(
  BuildContext context, {
  required List<GeoData> features,
  required Project project,
  required AppSettings settings,
}) =>
    showModalBottomSheet<GeoData>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FeaturePickSheet(
          features: features, project: project, settings: settings),
    );

class FeaturePickSheet extends StatelessWidget {
  /// Urutan dari hit-test: point terdekat → line terdekat → polygon terkecil.
  final List<GeoData> features;
  final Project project;
  final AppSettings settings;

  const FeaturePickSheet({
    super.key,
    required this.features,
    required this.project,
    required this.settings,
  });

  String _subtitle(GeoData data) {
    final t = data.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${t.day}/${t.month}/${t.year} ${two(t.hour)}:${two(t.minute)}';
    final by = data.collectedBy;
    return by == null || by.isEmpty ? when : '$by · $when';
  }

  @override
  Widget build(BuildContext context) {
    final geometry = styleGeometryForProject(project.geometryType);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${features.length} features here',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('Choose one to open.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final data in features)
                    ListTile(
                      leading: StyleSwatch(
                        style: effectiveFeatureStyle(
                            data, project.geometryType, settings),
                        geometry: geometry,
                      ),
                      title: Text(recordTitle(data, project),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_subtitle(data),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, data),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
