import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../services/storage_service.dart';
import '../../services/tracking/session_to_geodata.dart';
import '../../theme/app_theme.dart';
import '../dynamic_form.dart';

/// Tampilkan form atribut sebagai bottom sheet modal untuk menyimpan satu sesi
/// tracking ([points]) sebuah [project]. Mengembalikan `true` bila tersimpan.
///
/// Dipakai ulang oleh mode 1-project (stop→form) maupun panel multi-sesi. Bila
/// jumlah titik belum cukup untuk geometri project, langsung batal + snackbar.
Future<bool> showAttributeFormSheet(
  BuildContext context, {
  required Project project,
  required List<GeoPoint> points,
  String? username,
}) async {
  final geom = validateGeometry(project.geometryType, points.length);
  if (!geom.ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(geom.error ?? 'Titik belum cukup')),
    );
    return false;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AttributeFormSheet(
      project: project,
      points: points,
      username: username,
    ),
  );
  return result ?? false;
}

class AttributeFormSheet extends StatefulWidget {
  final Project project;
  final List<GeoPoint> points;
  final String? username;

  const AttributeFormSheet({
    super.key,
    required this.project,
    required this.points,
    this.username,
  });

  @override
  State<AttributeFormSheet> createState() => _AttributeFormSheetState();
}

class _AttributeFormSheetState extends State<AttributeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final StorageService _storage = StorageService();
  Map<String, dynamic> _formData = {};
  bool _saving = false;

  Future<void> _save() async {
    // Validasi form (peringatan field foto tak memblokir, seperti alur lama).
    _formKey.currentState?.validate();
    _formKey.currentState?.save(); // memicu DynamicForm.onSaved → _formData

    setState(() => _saving = true);
    try {
      final geoData = buildGeoData(
        id: const Uuid().v4(),
        project: widget.project,
        points: widget.points,
        formData: _formData,
        collectedBy: widget.username,
      );
      await _storage.saveGeoData(geoData);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.points.isNotEmpty ? widget.points.last : null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle + judul
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Isi Atribut — ${widget.project.name}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('${widget.points.length} titik',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: DynamicForm(
                      formFields: widget.project.formFields,
                      projectId: widget.project.id,
                      onSaved: (data) => _formData = data,
                      username: widget.username,
                      latitude: last?.latitude,
                      longitude: last?.longitude,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
