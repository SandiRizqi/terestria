import 'package:flutter/material.dart';

import '../../models/project_model.dart';
import '../../services/tracking/tracking_session_manager.dart';
import '../../theme/app_theme.dart';
import 'attribute_form_sheet.dart';

/// Teks banner "Tracking N project aktif" — null bila tak ada sesi.
String? activeTrackingBannerText(int count) =>
    count <= 0 ? null : 'Tracking $count project aktif';

/// Banner di atas daftar project: muncul saat ada sesi aktif, tap → panel.
class ActiveTrackingBanner extends StatelessWidget {
  final VoidCallback onTap;
  const ActiveTrackingBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final manager = TrackingSessionManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final text = activeTrackingBannerText(manager.activeCount);
        if (text == null) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      size: 12, color: Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text('Lihat',
                      style: TextStyle(
                          color: Color(0xFFB71C1C),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB71C1C)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tampilkan panel "Tracking Aktif" sebagai bottom sheet.
Future<void> showActiveTrackingPanel(
  BuildContext context, {
  required void Function(Project) onOpenProject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ActiveTrackingPanel(
      onOpenProject: (p) {
        Navigator.pop(context); // tutup panel
        onOpenProject(p);
      },
    ),
  );
}

/// Isi panel: daftar sesi aktif + aksi Stop&Simpan / Buka per project.
class ActiveTrackingPanel extends StatefulWidget {
  final void Function(Project) onOpenProject;
  const ActiveTrackingPanel({super.key, required this.onOpenProject});

  @override
  State<ActiveTrackingPanel> createState() => _ActiveTrackingPanelState();
}

class _ActiveTrackingPanelState extends State<ActiveTrackingPanel> {
  final TrackingSessionManager _manager = TrackingSessionManager.instance;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _stopAndSave(String projectId) async {
    final session = _manager.sessionFor(projectId);
    if (session == null) return;
    final saved = await showAttributeFormSheet(
      context,
      project: session.project,
      points: List.from(session.points),
    );
    if (saved) _manager.stop(projectId);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _manager.activeSessions;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record,
                    size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Text('Tracking Aktif (${sessions.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Tidak ada project yang sedang tracking.'),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  final dist = _manager.distanceOf(s.projectId);
                  return ListTile(
                    leading: const Icon(Icons.timeline, color: AppTheme.primaryGreen),
                    title: Text(s.project.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${s.pointCount} titik • ${dist.toStringAsFixed(0)} m'
                      '${s.paused ? ' • paused' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          key: ValueKey('open-${s.projectId}'),
                          onPressed: () => widget.onOpenProject(s.project),
                          child: const Text('Buka'),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton.icon(
                          key: ValueKey('stopsave-${s.projectId}'),
                          onPressed: () => _stopAndSave(s.projectId),
                          icon: const Icon(Icons.stop_rounded, size: 16),
                          label: const Text('Simpan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
