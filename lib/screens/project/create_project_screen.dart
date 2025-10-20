import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/project_model.dart';
import '../../models/form_field_model.dart';
import '../../services/storage_service.dart';
import '../../widgets/form_field_builder.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';

class CreateProjectScreen extends StatefulWidget {
  final Project? project; // for editing

  const CreateProjectScreen({Key? key, this.project}) : super(key: key);

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();
  final _uuid = const Uuid();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  GeometryType _selectedGeometry = GeometryType.point;
  List<FormFieldModel> _formFields = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project?.name ?? '');
    _descriptionController = TextEditingController(text: widget.project?.description ?? '');
    
    if (widget.project != null) {
      _selectedGeometry = widget.project!.geometryType;
      _formFields = List.from(widget.project!.formFields);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
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
      final project = Project(
        id: widget.project?.id ?? _uuid.v4(),
        name: _nameController.text,
        description: _descriptionController.text,
        geometryType: _selectedGeometry,
        formFields: _formFields,
        createdAt: widget.project?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _storageService.saveProject(project);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.project == null 
                ? 'Project created successfully' 
                : 'Project updated successfully'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving project: $e')),
        );
      }
    }
  }

  void _addFormField() async {
    final field = await showDialog<FormFieldModel>(
      context: context,
      builder: (context) => const FormFieldBuilderDialog(),
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
      builder: (context) => FormFieldBuilderDialog(field: _formFields[index]),
    );

    if (field != null) {
      setState(() {
        _formFields[index] = field;
      });
    }
  }

  void _deleteFormField(int index) {
    setState(() {
      _formFields.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project == null ? 'Create Project' : 'Edit Project'),
        actions: [
          const ConnectivityIndicator(
            showLabel: false,
            iconSize: 24,
          ),
          const SizedBox(width: 8),
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProject,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Project Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter project name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Geometry Type
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Geometry Type',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _buildGeometryTypeSelector(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Form Fields Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Form Fields',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        ElevatedButton.icon(
                          onPressed: _addFormField,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Field'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_formFields.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No form fields added yet.\nClick "Add Field" to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
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
                          return _buildFormFieldCard(field, index);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeometryTypeSelector() {
    return Column(
      children: [
        RadioListTile<GeometryType>(
          title: const Text('Point'),
          subtitle: const Text('Single location marker'),
          value: GeometryType.point,
          groupValue: _selectedGeometry,
          onChanged: (value) => setState(() => _selectedGeometry = value!),
          secondary: const Icon(Icons.place),
        ),
        RadioListTile<GeometryType>(
          title: const Text('Line'),
          subtitle: const Text('Path or route'),
          value: GeometryType.line,
          groupValue: _selectedGeometry,
          onChanged: (value) => setState(() => _selectedGeometry = value!),
          secondary: const Icon(Icons.timeline),
        ),
        RadioListTile<GeometryType>(
          title: const Text('Polygon'),
          subtitle: const Text('Area or boundary'),
          value: GeometryType.polygon,
          groupValue: _selectedGeometry,
          onChanged: (value) => setState(() => _selectedGeometry = value!),
          secondary: const Icon(Icons.crop_square),
        ),
      ],
    );
  }

  Widget _buildFormFieldCard(FormFieldModel field, int index) {
    IconData icon;
    switch (field.type) {
      case FieldType.text:
        icon = Icons.text_fields;
        break;
      case FieldType.number:
        icon = Icons.numbers;
        break;
      case FieldType.date:
        icon = Icons.calendar_today;
        break;
      case FieldType.dropdown:
        icon = Icons.arrow_drop_down_circle;
        break;
      case FieldType.checkbox:
        icon = Icons.check_box;
        break;
      case FieldType.photo:
        icon = Icons.photo_camera;
        break;
    }

    return Card(
      key: ValueKey(field.id),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(field.label),
        subtitle: Text(
          '${field.type.toString().split('.').last}${field.required ? ' • Required' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editFormField(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              color: Colors.red,
              onPressed: () => _deleteFormField(index),
            ),
          ],
        ),
      ),
    );
  }
}
