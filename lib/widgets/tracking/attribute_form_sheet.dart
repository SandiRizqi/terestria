import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/feature_style.dart';
import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../services/tracking/session_to_geodata.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';
import '../dynamic_form.dart';
import '../style/feature_style_section.dart';

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
    showInfoFeedback(context, geom.error ?? 'Not enough points to save.',
        warning: true);
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

  /// Untuk test; default [StorageService].
  final StorageService? storageService;

  const AttributeFormSheet({
    super.key,
    required this.project,
    required this.points,
    this.username,
    this.storageService,
  });

  @override
  State<AttributeFormSheet> createState() => _AttributeFormSheetState();
}

class _AttributeFormSheetState extends State<AttributeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final StorageService _storage =
      widget.storageService ?? StorageService();
  final DynamicFormController _formController = DynamicFormController();
  Map<String, dynamic> _formData = {};

  /// Style feature (null = ikut default Settings), sama dengan form
  /// "Survey data".
  LayerStyle? _style;
  bool _saving = false;

  Future<void> _save() async {
    _formKey.currentState?.save(); // memicu DynamicForm.onSaved → _formData
    final formValid = _formKey.currentState?.validate() ?? true;
    // Form belum lengkap → DIBLOKIR (dulu tetap tersimpan) & gulir ke field.
    final issues = formFieldIssues(widget.project.formFields, _formData);
    if (issues.isNotEmpty || !formValid) {
      if (issues.isNotEmpty) _formController.scrollTo(issues.first.field.label);
      showInfoFeedback(
        context,
        issues.isEmpty
            ? 'Some fields need attention.'
            : '"${issues.first.field.label}" ${issues.first.message}'
                '${issues.length > 1 ? ' (+${issues.length - 1} more)' : ''}.',
        warning: true,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Kolektor = user yang login bila pemanggil tak menyertakannya (panel
      // Tracking Aktif dulu menyimpan tanpa kolektor → record tak bisa diedit).
      final collector =
          widget.username ?? (await AuthService().getUser())?.username;
      final geoData = buildGeoData(
        id: const Uuid().v4(),
        project: widget.project,
        points: widget.points,
        formData: _formData,
        collectedBy: collector,
        style: _style,
      );
      await _storage.saveGeoData(geoData);
      logInfo(
          'Saved tracking record ${geoData.id} (${geoData.points.length} '
          'points) in "${widget.project.name}"',
          tag: 'SESSION');
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorFeedback(context, 'Could not save the record',
            error: e, stack: st, tag: 'SESSION');
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
                        'Attributes — ${widget.project.name}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('${widget.points.length} points',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        RequiredFieldsProgress(
                          fields: widget.project.formFields,
                          data: _formData,
                        ),
                        DynamicForm(
                          formFields: widget.project.formFields,
                          projectId: widget.project.id,
                          controller: _formController,
                          onSaved: (data) => _formData = data,
                          onChanged: () {
                            if (mounted) setState(() {});
                          },
                          username: widget.username,
                          latitude: last?.latitude,
                          longitude: last?.longitude,
                        ),
                        const SizedBox(height: 16),
                        FeatureStyleSection(
                          geometryType: widget.project.geometryType,
                          style: _style,
                          defaultStyle: defaultFeatureStyle(
                              widget.project.geometryType,
                              SettingsService().settings),
                          onChanged: (style) => setState(() => _style = style),
                        ),
                      ],
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
                    label: Text(_saving ? 'Saving…' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
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
