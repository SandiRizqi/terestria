import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/project_model.dart';
import '../../services/tracking/tracking_engine.dart';
import '../../services/tracking/tracking_session.dart';
import '../../services/tracking/tracking_session_manager.dart';
import '../../theme/app_theme.dart';
import 'attribute_form_sheet.dart';

// ─── Helper tampilan (murni, teruji) ─────────────────────────────────────────

/// Label status sesi untuk UI.
String sessionStateLabel(SessionState state) => switch (state) {
      SessionState.recording => 'Merekam',
      SessionState.paused => 'Jeda',
      SessionState.pendingSave => 'Belum disimpan',
    };

Color sessionStateColor(SessionState state) => switch (state) {
      SessionState.recording => AppTheme.errorColor,
      SessionState.paused => AppTheme.warningColor,
      SessionState.pendingSave => AppTheme.primaryBlue,
    };

/// Ringkasan banner, mis. "2 merekam · 1 belum disimpan"; null bila kosong.
String? activeTrackingBannerText({
  required int recording,
  int paused = 0,
  int pending = 0,
}) {
  final parts = [
    if (recording > 0) '$recording merekam',
    if (paused > 0) '$paused jeda',
    if (pending > 0) '$pending belum disimpan',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = two(d.inMinutes % 60);
  final s = two(d.inSeconds % 60);
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.toStringAsFixed(0)} m'
    : '${(meters / 1000).toStringAsFixed(2)} km';

/// "baru saja" / "30 dtk lalu" / "3 mnt lalu" — null bila belum ada titik.
String? lastFixAgo(DateTime? last, DateTime now) {
  if (last == null) return null;
  final d = now.difference(last);
  if (d.inSeconds < 5) return 'baru saja';
  if (d.inMinutes < 1) return '${d.inSeconds} dtk lalu';
  if (d.inHours < 1) return '${d.inMinutes} mnt lalu';
  return '${d.inHours} jam lalu';
}

/// Urutan panel: merekam → jeda → belum disimpan; terbaru di atas.
List<TrackingSession> sortSessionsForPanel(Iterable<TrackingSession> sessions) =>
    sessions.toList()
      ..sort((a, b) {
        final byState = a.state.index.compareTo(b.state.index);
        return byState != 0 ? byState : b.startedAt.compareTo(a.startedAt);
      });

/// Durasi sesi: berjalan untuk sesi hidup; draft berhenti di titik terakhir.
Duration sessionElapsed(TrackingSession s, DateTime now) {
  if (!s.pendingSave) return now.difference(s.startedAt);
  if (s.points.isEmpty) return Duration.zero;
  return s.points.last.timestamp.difference(s.startedAt);
}

// ─── Banner di atas daftar project ───────────────────────────────────────────

/// Banner di atas daftar project: ringkasan per status + nama project; tap →
/// panel. Hilang bila tak ada sesi.
class ActiveTrackingBanner extends StatelessWidget {
  final VoidCallback onTap;
  const ActiveTrackingBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final manager = TrackingSessionManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final recording = manager.recordingCount;
        final paused = manager.liveCount - recording;
        final pending = manager.activeCount - manager.liveCount;
        final text = activeTrackingBannerText(
            recording: recording, paused: paused, pending: pending);
        if (text == null) return const SizedBox.shrink();

        final color = sessionStateColor(recording > 0
            ? SessionState.recording
            : paused > 0
                ? SessionState.paused
                : SessionState.pendingSave);
        final names = sortSessionsForPanel(manager.activeSessions)
            .map((s) => s.project.name)
            .toList();
        final namesText = names.length <= 2
            ? names.join(', ')
            : '${names.take(2).join(', ')} +${names.length - 2}';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    _StatusDot(color: color, pulsing: recording > 0),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            namesText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Text('Kelola',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Titik status; berdenyut saat ada sesi yang merekam.
class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _StatusDot({required this.color, required this.pulsing});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pulsing) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
        child: Icon(Icons.fiber_manual_record, size: 12, color: widget.color),
      );
}

// ─── Panel "Tracking Aktif" ──────────────────────────────────────────────────

/// Tampilkan panel "Tracking Aktif" sebagai bottom sheet.
Future<void> showActiveTrackingPanel(
  BuildContext context, {
  required void Function(Project) onOpenProject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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

/// Pusat kendali semua sesi: status live + Jeda/Lanjutkan, Simpan, Buang, Buka
/// — tanpa perlu membuka layar data collector tiap project.
class ActiveTrackingPanel extends StatefulWidget {
  final void Function(Project) onOpenProject;

  /// Menyalakan feed GPS saat melanjutkan sesi (default: TrackingEngine).
  final Future<bool> Function()? ensureRunning;

  const ActiveTrackingPanel({
    super.key,
    required this.onOpenProject,
    this.ensureRunning,
  });

  @override
  State<ActiveTrackingPanel> createState() => _ActiveTrackingPanelState();
}

class _ActiveTrackingPanelState extends State<ActiveTrackingPanel> {
  final TrackingSessionManager _manager = TrackingSessionManager.instance;
  Timer? _clock; // durasi & "titik terakhir" berjalan tiap detik

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _manager.liveCount > 0) setState(() {});
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _manager.removeListener(_onChanged);
    super.dispose();
  }

  Future<bool> _ensureRunning() =>
      (widget.ensureRunning ?? TrackingEngine.instance.ensureRunning)();

  /// Jeda sesi yang merekam; lanjutkan sesi jeda/draft (menyalakan GPS).
  Future<void> _toggle(TrackingSession s) async {
    if (s.isRecording) {
      _manager.pause(s.projectId);
      return;
    }
    final prev = s.state;
    _manager.resume(s.projectId);
    final ok = await _ensureRunning();
    if (ok || !mounted) return;
    if (prev == SessionState.pendingSave) {
      _manager.finish(s.projectId);
    } else {
      _manager.pause(s.projectId);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Gagal menyalakan GPS background. Cek izin lokasi.'),
      backgroundColor: AppTheme.errorColor,
    ));
  }

  /// Stop (jadi draft) lalu buka form atribut. Batal → tetap draft
  /// "Belum disimpan" (bisa dilanjutkan/disimpan nanti).
  Future<void> _stopAndSave(TrackingSession s) async {
    if (s.isLive) _manager.finish(s.projectId);
    final saved = await showAttributeFormSheet(
      context,
      project: s.project,
      points: List.of(s.points),
    );
    if (!saved) return;
    _manager.stop(s.projectId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Data "${s.project.name}" tersimpan'),
        backgroundColor: AppTheme.successColor,
      ));
    }
  }

  /// Hentikan & BUANG sesi tanpa menyimpan (mis. titik belum cukup) —
  /// mencegah sesi "zombie" yang tak bisa dilepas.
  Future<void> _discard(TrackingSession s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buang sesi tracking?'),
        content: Text(
            '${s.pointCount} titik "${s.project.name}" yang belum disimpan akan hilang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (confirm == true) _manager.stop(s.projectId);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = sortSessionsForPanel(_manager.activeSessions);
    final recording = _manager.recordingCount;
    final summary = activeTrackingBannerText(
      recording: recording,
      paused: _manager.liveCount - recording,
      pending: _manager.activeCount - _manager.liveCount,
    );
    final now = DateTime.now();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tracking Aktif (${sessions.length})',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  if (summary != null) ...[
                    const SizedBox(height: 2),
                    Text(summary,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.route_outlined,
                        size: 36, color: AppTheme.textSecondary),
                    SizedBox(height: 8),
                    Text('Tidak ada project yang sedang tracking.',
                        textAlign: TextAlign.center),
                    SizedBox(height: 4),
                    Text('Mulai tracking dari halaman data collector project.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  itemCount: sessions.length,
                  itemBuilder: (_, i) => _SessionCard(
                    session: sessions[i],
                    now: now,
                    onToggle: () => _toggle(sessions[i]),
                    onOpen: () => widget.onOpenProject(sessions[i].project),
                    onSave: () => _stopAndSave(sessions[i]),
                    onDiscard: () => _discard(sessions[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TrackingSession session;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _SessionCard({
    required this.session,
    required this.now,
    required this.onToggle,
    required this.onOpen,
    required this.onSave,
    required this.onDiscard,
  });

  IconData get _geometryIcon => switch (session.project.geometryType) {
        GeometryType.point => Icons.place_outlined,
        GeometryType.line => Icons.timeline,
        GeometryType.polygon => Icons.pentagon_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final s = session;
    final stateColor = sessionStateColor(s.state);
    final last = s.points.isEmpty ? null : s.points.last.timestamp;
    final ago = s.isRecording ? lastFixAgo(last, now) : null;
    final id = s.projectId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: stateColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                  child: Icon(_geometryIcon,
                      size: 18, color: AppTheme.primaryGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                _StateChip(state: s.state),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Metric(
                  icon: s.source == TrackSource.emlid
                      ? Icons.satellite_alt_outlined
                      : Icons.smartphone,
                  text: s.source == TrackSource.emlid ? 'RTK' : 'GPS HP',
                ),
                _Metric(icon: Icons.scatter_plot_outlined, text: '${s.pointCount} titik'),
                _Metric(
                    icon: Icons.straighten, text: formatDistance(s.distanceMeters)),
                _Metric(
                    icon: Icons.timer_outlined,
                    text: formatElapsed(sessionElapsed(s, now))),
                if (ago != null) _Metric(icon: Icons.gps_fixed, text: ago),
              ],
            ),
            const SizedBox(height: 4),
            // Wrap (bukan Row): di HP sempit tombol turun baris, tak overflow.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              children: [
                TextButton(
                  key: ValueKey('toggle-$id'),
                  onPressed: onToggle,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          s.isRecording
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18),
                      const SizedBox(width: 4),
                      Text(s.isRecording ? 'Jeda' : 'Lanjutkan'),
                    ],
                  ),
                ),
                TextButton(
                  key: ValueKey('open-$id'),
                  onPressed: onOpen,
                  child: const Text('Buka'),
                ),
                IconButton(
                  key: ValueKey('discard-$id'),
                  tooltip: 'Buang',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppTheme.errorColor),
                  onPressed: onDiscard,
                ),
                FilledButton.icon(
                  key: ValueKey('stopsave-$id'),
                  onPressed: onSave,
                  icon: Icon(s.pendingSave ? Icons.save_outlined : Icons.stop_rounded,
                      size: 16),
                  label: Text(s.pendingSave ? 'Simpan' : 'Stop & Simpan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final SessionState state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = sessionStateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, size: 8, color: color),
          const SizedBox(width: 4),
          Text(sessionStateLabel(state),
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Metric({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      );
}
