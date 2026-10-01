import 'package:flutter/material.dart';

import '../../models/form_field_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../models/sync_conflict.dart';
import '../../services/sync_service.dart';
import '../../utils/field_values.dart';

/// Satu record berkonflik + versinya di HP (null bila sudah tak ada di HP).
class ConflictEntry {
  final SyncConflict conflict;
  final GeoData? local;
  const ConflictEntry({required this.conflict, this.local});
}

typedef ResolveConflict = Future<SyncResult> Function(String geoDataId);

/// Perbedaan versi di HP ([mine]) dan versi server ([server]) untuk user:
/// field (sesuai urutan form), lalu geometri, lalu jumlah foto.
List<String> conflictChangeSummary(
    GeoData mine, GeoData server, Project project) {
  final changes = <String>[];
  final photoFields = <FormFieldModel>[];
  for (final field in project.formFields) {
    if (field.type == FieldType.photo) {
      photoFields.add(field);
      continue;
    }
    final a = _display(field, mine.formData[field.label]);
    final b = _display(field, server.formData[field.label]);
    if (a != b) changes.add('${field.label}: ${_quote(a)} → ${_quote(b)}');
  }
  if (mine.points.length != server.points.length) {
    changes.add('Points: ${mine.points.length} → ${server.points.length}');
  } else if (_geometryMoved(mine.points, server.points)) {
    changes.add('Location / shape changed');
  }
  for (final field in photoFields) {
    final a = _photoCount(mine.formData[field.label]);
    final b = _photoCount(server.formData[field.label]);
    if (a != b) changes.add('${field.label}: $a → $b photos');
  }
  return changes;
}

/// Nilai terformat ([displayFieldValue]); bentuk simpan yang berbeda untuk
/// nilai yang sama (4 / "4", 36 / 36.0) tidak dianggap perbedaan.
String _display(FormFieldModel field, Object? v) =>
    displayFieldValue(field, v).trim();

/// Satu baris: baris baru teks panjang jadi spasi, maks 30 karakter.
String _quote(String s) {
  if (s.isEmpty) return '(empty)';
  final line = s.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  return '"${line.length > 30 ? '${line.substring(0, 30)}…' : line}"';
}

int _photoCount(Object? v) {
  if (v is List) return v.length;
  return (v == null || v.toString().isEmpty) ? 0 : 1;
}

bool _geometryMoved(List<GeoPoint> a, List<GeoPoint> b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i].latitude - b[i].latitude).abs() > 1e-7 ||
        (a[i].longitude - b[i].longitude).abs() > 1e-7) {
      return true;
    }
  }
  return false;
}

String _stamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.day}/${l.month} ${two(l.hour)}:${two(l.minute)}';
}

/// Banner di detail project: ada record yang berkonflik.
class ConflictBanner extends StatelessWidget {
  final int count;
  final VoidCallback onResolve;
  const ConflictBanner({super.key, required this.count, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.sync_problem_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1
                    ? '1 record was changed on the server'
                    : '$count records were changed on the server',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
            TextButton(onPressed: onResolve, child: const Text('Resolve')),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet penyelesaian konflik.
Future<void> showConflictResolutionSheet(
  BuildContext context, {
  required Project project,
  required List<ConflictEntry> entries,
  required ResolveConflict keepMine,
  required ResolveConflict useServer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: ConflictResolutionSheet(
        project: project,
        entries: entries,
        keepMine: keepMine,
        useServer: useServer,
      ),
    ),
  );
}

/// Daftar record berkonflik: apa yang beda, lalu **Keep mine** (unggah versi
/// HP, menimpa server) atau **Use server version** (ganti versi HP).
class ConflictResolutionSheet extends StatefulWidget {
  final Project project;
  final List<ConflictEntry> entries;
  final ResolveConflict keepMine;
  final ResolveConflict useServer;

  const ConflictResolutionSheet({
    super.key,
    required this.project,
    required this.entries,
    required this.keepMine,
    required this.useServer,
  });

  @override
  State<ConflictResolutionSheet> createState() =>
      _ConflictResolutionSheetState();
}

class _ConflictResolutionSheetState extends State<ConflictResolutionSheet> {
  late final List<ConflictEntry> _entries = List.of(widget.entries);
  final Set<String> _busy = {};
  final Map<String, String> _errors = {};

  Future<void> _resolve(ConflictEntry entry, ResolveConflict action) async {
    final id = entry.conflict.geoDataId;
    setState(() {
      _busy.add(id);
      _errors.remove(id);
    });
    SyncResult result;
    try {
      result = await action(id);
    } catch (e) {
      result = SyncResult(success: false, message: 'Something went wrong: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (result.success) {
        _entries.remove(entry);
      } else {
        _errors[id] = result.message;
      }
    });
  }

  String _title(ConflictEntry e) {
    final record = e.local ?? e.conflict.serverVersion;
    if (record != null) {
      for (final field in widget.project.formFields) {
        if (field.type == FieldType.photo) continue;
        final value = _display(field, record.formData[field.label]);
        if (value.isNotEmpty) {
          return value.length > 40 ? '${value.substring(0, 40)}…' : value;
        }
      }
    }
    final id = e.conflict.geoDataId;
    return 'Record ${id.length > 8 ? id.substring(0, 8) : id}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Changed on the server',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'Someone else edited these records on the server after you '
                'last downloaded them. Choose which version to keep for each '
                'record.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('All conflicts are resolved.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [for (final e in _entries) _card(e)],
                ),
        ),
      ],
    );
  }

  Widget _card(ConflictEntry e) {
    final id = e.conflict.geoDataId;
    final server = e.conflict.serverVersion;
    final local = e.local;
    final changes = (local != null && server != null)
        ? conflictChangeSummary(local, server, widget.project)
        : const <String>[];
    final busy = _busy.contains(id);
    final error = _errors[id];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(e),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              local == null
                  ? 'On this phone: no longer here'
                  : 'On this phone: edited ${_stamp(local.updatedAt)}',
              style: const TextStyle(fontSize: 12.5),
            ),
            Text(
              server == null
                  ? 'On the server: version not available'
                  : 'On the server: ${server.collectedBy ?? 'someone'}, '
                      '${_stamp(server.updatedAt)}',
              style: const TextStyle(fontSize: 12.5),
            ),
            if (changes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final c in changes.take(4))
                Text('• $c',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
              if (changes.length > 4)
                Text('…and ${changes.length - 4} more',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error,
                  style: TextStyle(fontSize: 12.5, color: Colors.red[800])),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => _resolve(e, widget.useServer),
                  child: const Text('Use server version'),
                ),
                FilledButton(
                  onPressed: busy || local == null
                      ? null
                      : () => _resolve(e, widget.keepMine),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Keep mine'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
