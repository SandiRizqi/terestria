import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/feature_style.dart';
import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';
import '../../services/geometry_edit.dart';
import '../../services/photo_sync_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/dynamic_form.dart';
import '../../widgets/collection/accuracy_summary.dart';
import '../../widgets/map/tools/measure_math.dart';
import '../../widgets/style/feature_style_section.dart';
import 'geometry_editor_screen.dart';

/// Edit atribut DAN geometri record (koreksi vertex lewat crosshair) — dulu
/// hanya atribut, sehingga titik yang salah harus dihapus & diambil ulang di
/// lokasi.
class EditGeoDataScreen extends StatefulWidget {
  final GeoData geoData;
  final Project project;

  /// Untuk test; default [StorageService].
  final StorageService? storageService;

  const EditGeoDataScreen({
    Key? key,
    required this.geoData,
    required this.project,
    this.storageService,
  }) : super(key: key);

  @override
  State<EditGeoDataScreen> createState() => _EditGeoDataScreenState();
}

class _EditGeoDataScreenState extends State<EditGeoDataScreen> {
  late final StorageService _storageService =
      widget.storageService ?? StorageService();
  final _formKey = GlobalKey<FormState>();
  final DynamicFormController _formController = DynamicFormController();
  late Map<String, dynamic> _formData;
  late List<GeoPoint> _points;

  /// Style feature (null = ikut default Settings).
  LayerStyle? _style;
  bool _isSaving = false;

  bool get _geometryChanged =>
      !GeometryEditSession.samePositions(_points, widget.geoData.points);

  @override
  void initState() {
    super.initState();
    _formData = Map<String, dynamic>.from(widget.geoData.formData);
    _points = List.of(widget.geoData.points);
    _style = widget.geoData.style;
  }

  Future<void> _editGeometry() async {
    final result = await Navigator.push<List<GeoPoint>>(
      context,
      MaterialPageRoute(
        builder: (_) => GeometryEditorScreen(
          type: widget.project.geometryType,
          points: _points,
          minAccuracy: widget.project.minAccuracy,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _points = result);
  }

  Future<void> _saveChanges() async {
    // onSaved DynamicForm mengisi _formData.
    _formKey.currentState?.save();
    final formValid = _formKey.currentState?.validate() ?? true;
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
    final minPoints =
        GeometryEditSession.minPoints(widget.project.geometryType);
    if (_points.length < minPoints) {
      showInfoFeedback(context,
          'This ${widget.project.geometryType.name} needs at least $minPoints points.',
          warning: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Foto yang diunggah auto-sync selama user mengedit: pertahankan
      // serverKey-nya (form ini berangkat dari snapshot saat layar dibuka).
      final latest = await _storageService.getGeoDataById(widget.geoData.id);
      final formData = latest == null
          ? _formData
          : PhotoSyncService.mergeUploadedPhotoKeys(
              _formData, latest.formData, widget.project);
      final updatedGeoData = widget.geoData.copyWith(
        formData: formData,
        points: _points,
        updatedAt: DateTime.now(),
        isSynced: false, // ada perubahan → perlu diunggah ulang
        style: _style,
        clearStyle: _style == null,
      );
      await _storageService.saveGeoData(updatedGeoData);
      logInfo(
          'Edited record ${widget.geoData.id} in "${widget.project.name}"'
          '${_geometryChanged ? ' (geometry ${widget.geoData.points.length} → ${_points.length} points)' : ''}',
          tag: 'EDIT');
      if (!mounted) return;
      Navigator.pop(context, true); // true → layar sebelumnya memuat ulang
      showInfoFeedback(context, 'Changes saved', success: true,
          duration: const Duration(seconds: 2));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showErrorFeedback(context, 'Could not save the changes',
          error: e, stack: st, tag: 'EDIT');
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('The corrected geometry has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  String _measurement() {
    final settings = SettingsService().settings;
    final pts = _points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    switch (widget.project.geometryType) {
      case GeometryType.point:
        if (pts.isEmpty) return '-';
        return '${pts.first.latitude.toStringAsFixed(6)}, '
            '${pts.first.longitude.toStringAsFixed(6)}';
      case GeometryType.line:
        return settings.formatDistance(polylineLengthMeters(pts));
      case GeometryType.polygon:
        return settings.formatArea(polygonAreaSqMeters(pts));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.project.geometryType;
    return PopScope(
      canPop: !_geometryChanged || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryGreen,
          elevation: 0,
          title: const Text(
            'Edit record',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          actions: [
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check_rounded, size: 28),
                onPressed: _saveChanges,
                tooltip: 'Save changes',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingMedium),
                  children: [
                    // Geometri (bisa dikoreksi)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _geometryChanged
                                ? Colors.orange.shade300
                                : Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Geometry',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (_geometryChanged)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('Edited — not saved yet',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade900)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoItem(
                                    'Type', type.name.toUpperCase()),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildInfoItem(
                                    'Points', '${_points.length}'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoItem(
                            switch (type) {
                              GeometryType.point => 'Coordinates',
                              GeometryType.line => 'Length',
                              GeometryType.polygon => 'Area',
                            },
                            _measurement(),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoItem(
                            'Collected',
                            '${_formatDate(widget.geoData.createdAt)}'
                                '${widget.geoData.collectedBy == null ? '' : ' by ${widget.geoData.collectedBy}'}',
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isSaving ? null : _editGeometry,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                foregroundColor: AppTheme.primaryColor,
                              ),
                              icon: const Icon(Icons.edit_location_alt_rounded),
                              label: Text(type == GeometryType.point
                                  ? 'Move the point'
                                  : 'Correct points on the map'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    AccuracySummary(
                      geometryType: widget.project.geometryType,
                      points: _points,
                      limit: widget.project.minAccuracy,
                    ),
                    RequiredFieldsProgress(
                      fields: widget.project.formFields,
                      data: _formData,
                    ),
                    // Tanpa projectId: nilai yang di-pin untuk koleksi baru
                    // TIDAK boleh menimpa nilai record yang sedang diedit.
                    DynamicForm(
                      formFields: widget.project.formFields,
                      initialData: _formData,
                      controller: _formController,
                      onSaved: (data) => _formData = data,
                      onChanged: () {
                        if (mounted) setState(() {});
                      },
                      username: widget.geoData.collectedBy,
                      latitude:
                          _points.isNotEmpty ? _points.first.latitude : null,
                      longitude:
                          _points.isNotEmpty ? _points.first.longitude : null,
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

                    const SizedBox(height: 100), // ruang untuk tombol
                  ],
                ),
              ),

              // Save Button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[600],
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Saving…',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_outlined, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Save changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
