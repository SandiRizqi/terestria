import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/project_model.dart';
import '../../models/form_field_model.dart';
import '../../services/storage_service.dart';
import '../../services/sync_service.dart';
import '../../services/connectivity_service.dart';
import '../../utils/field_values.dart' show formatNumber;
import '../../widgets/project/create_project_parts.dart';
import '../../widgets/project/project_rules_section.dart';
import '../../widgets/form_field_builder.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/light_app_bar.dart';
import '../../utils/ui_feedback.dart';

class CreateProjectScreen extends StatefulWidget {
  final Project? project; // for editing
  final bool isFromTemplate; // to indicate if project is from template

  const CreateProjectScreen({Key? key, this.project, this.isFromTemplate = false}) : super(key: key);

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();
  final _syncService = SyncService();
  final _connectivityService = ConnectivityService();
  final _uuid = const Uuid();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  GeometryType _selectedGeometry = GeometryType.point;
  List<FormFieldModel> _formFields = [];
  // Aturan project: akurasi minimum & id field kombinasi unik (urut).
  late final TextEditingController _minAccuracyController;
  List<String> _uniqueFieldIds = [];
  bool _isSaving = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project?.name ?? '');
    _descriptionController = TextEditingController(text: widget.project?.description ?? '');
    
    final minAccuracy = widget.project?.minAccuracy;
    _minAccuracyController = TextEditingController(
        text: minAccuracy == null ? '' : formatNumber(minAccuracy));
    if (widget.project != null) {
      _selectedGeometry = widget.project!.geometryType;
      _formFields = List.from(widget.project!.formFields);
      _uniqueFieldIds =
          uniqueFieldIdsFromLabels(_formFields, widget.project!.uniqueFields);
    } else {
      // Untuk project baru, tambahkan field "Name" secara default
      _formFields = [
        FormFieldModel(
          id: _uuid.v4(),
          label: 'Name',
          type: FieldType.text,
          required: true,
        ),
      ];
    }
    
    _initConnectivity();
  }

  void _initConnectivity() {
    _connectivityService.startMonitoring();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _minAccuracyController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_formFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one form field')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Ambil username dari AuthService untuk project baru
      String? createdBy = widget.project?.createdBy;
      if (widget.project == null) {
        // Hanya set createdBy untuk project baru
        final authService = AuthService();
        final user = await authService.getUser();
        createdBy = user?.username;
      }

      final keyIds = validUniqueFieldIds(_formFields, _uniqueFieldIds);
      final project = Project(
        id: widget.project?.id ?? _uuid.v4(),
        name: _nameController.text,
        description: _descriptionController.text,
        geometryType: _selectedGeometry,
        // Field kombinasi unik selalu wajib diisi.
        formFields: withRequiredKeyFields(_formFields, keyIds),
        createdAt: widget.project?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: createdBy,
        minAccuracy: minAccuracyFromInput(_minAccuracyController.text),
        uniqueFields: uniqueFieldLabels(_formFields, keyIds),
      );

      await _storageService.saveProject(project);

      if (mounted) {
        // Tanya user apakah ingin sync project
        final shouldSync = await _showSyncDialog();
        
        if (shouldSync == true && _isOnline) {
          await _syncProjectToServer(project);
        } else {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.project == null 
                  ? 'Project created successfully' 
                  : 'Project updated successfully'),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loggedErrorMessage('Could not save the project', e, tag: 'PROJECT'))),
        );
      }
    }
  }

  Future<bool?> _showSyncDialog() async {
    if (!_isOnline) {
      return false;
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cloud_upload, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            const Text('Sync Project'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project == null 
                  ? 'Project has been saved locally.' 
                  : 'Project has been updated locally.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Do you want to sync this project to the server now?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This will upload the project structure to the server.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('Sync Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncProjectToServer(Project project) async {
    // Show syncing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing project to server...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _syncService.syncProject(project);
      
      if (mounted) {
        Navigator.pop(context); // Close syncing dialog
        
        if (result.success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.project == null
                          ? 'Project created and synced successfully'
                          : 'Project updated and synced successfully',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Sync failed, but project is saved locally
          final retry = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('Sync Failed'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Project saved locally but failed to sync to server:'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      result.message,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You can sync it later from the project detail screen.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );

          if (retry == true) {
            await _syncProjectToServer(project);
          } else {
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close syncing dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(loggedErrorMessage('Could not upload the project', e, tag: 'SYNC'))),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
        
        Navigator.pop(context, true);
      }
    }
  }

  void _addFormField() async {
    final field = await showDialog<FormFieldModel>(
      context: context,
      builder: (context) => FormFieldBuilderDialog(
        existingFields: _formFields, // Pass existing fields untuk validasi
      ),
    );

    if (field != null) {
      setState(() {
        _formFields.add(field);
      });
    }
  }

  void _editFormField(int index) async {
    final field = await showDialog<FormFieldModel>(
      context: context,
      builder: (context) => FormFieldBuilderDialog(
        field: _formFields[index],
        existingFields: _formFields, // Pass existing fields untuk validasi
        lockRequired: _uniqueFieldIds.contains(_formFields[index].id),
      ),
    );

    if (field != null) {
      setState(() {
        _formFields[index] = field;
        // Ganti nama ikut otomatis (dilacak lewat id); tipe yang tak lagi
        // memenuhi syarat keluar dari kombinasi.
        _uniqueFieldIds = validUniqueFieldIds(_formFields, _uniqueFieldIds);
      });
    }
  }

  void _deleteFormField(int index) {
    setState(() {
      _formFields.removeAt(index);
      _uniqueFieldIds = validUniqueFieldIds(_formFields, _uniqueFieldIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.project != null;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      // Bar terang seperti template: tutup, judul, tombol Save.
      appBar: lightAppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          isEditing ? 'Edit project' : 'New project',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          const ConnectivityIndicator(
            showLabel: false,
            iconSize: 20,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _isSaving ? null : _saveProject,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const FormSectionLabel('Project Name'),
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration('e.g. Palm Estate · Block D'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter project name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Description'),
              TextFormField(
                controller: _descriptionController,
                decoration: _inputDecoration('What is this project for?'),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FormSectionLabel(
                'Geometry Type',
                trailing: isEditing ? _lockedBadge() : null,
              ),
              GeometrySegmentedControl(
                value: _selectedGeometry,
                onChanged: isEditing
                    ? null
                    : (type) => setState(() => _selectedGeometry = type),
              ),
              const SizedBox(height: 24),
              _buildFieldsHeader(isEditing),
              if (_formFields.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No form fields yet. Tap "Add Field" to create one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  // Seret hanya lewat pegangan di kartu; ketuk kartu = edit.
                  buildDefaultDragHandles: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _formFields.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _formFields.removeAt(oldIndex);
                      _formFields.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final field = _formFields[index];
                    return FormFieldCard(
                      key: ValueKey(field.id),
                      field: field,
                      isUniqueKey: _uniqueFieldIds.contains(field.id),
                      dragHandle: isEditing
                          ? null
                          : ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.drag_indicator_rounded,
                                    color: Colors.grey[400]),
                              ),
                            ),
                      onTap: isEditing ? null : () => _editFormField(index),
                      onDelete:
                          isEditing ? null : () => _deleteFormField(index),
                    );
                  },
                ),
              if (!isEditing) ...[
                const SizedBox(height: 4),
                DashedAddButton(label: 'Add Field', onPressed: _addFormField),
              ],
              const SizedBox(height: 24),

              // Project rules: akurasi minimum & kombinasi unik
              Container(
                decoration: AppTheme.getCardDecoration,
                padding: const EdgeInsets.all(20),
                child: ProjectRulesSection(
                  minAccuracyController: _minAccuracyController,
                  fields: _formFields,
                  uniqueFieldIds: _uniqueFieldIds,
                  onUniqueFieldIdsChanged: (ids) => setState(() {
                    _uniqueFieldIds = ids;
                    _formFields = withRequiredKeyFields(_formFields, ids);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.cardBackground,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2),
      ),
    );
  }

  /// "FORM FIELDS · n" + petunjuk seret, atau tanda terkunci saat edit.
  Widget _buildFieldsHeader(bool isEditing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'FORM FIELDS · ${_formFields.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (isEditing)
            Flexible(child: _lockedBadge())
          else if (_formFields.length > 1)
            const Text(
              'Drag to reorder',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }

  /// Tanda "Cannot be changed" (geometri & field project yang sudah ada).
  Widget _lockedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 14, color: Colors.orange[700]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Cannot be changed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
