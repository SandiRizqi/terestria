import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';
import 'photo_field_widget.dart';

class DynamicForm extends StatefulWidget {
  final List<FormFieldModel> formFields;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback? onChanged;
  final Map<String, dynamic>? initialData; // Add initial data support

  const DynamicForm({
    Key? key,
    required this.formFields,
    required this.onSaved,
    this.onChanged,
    this.initialData,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  late Map<String, dynamic> _formData;
  final Map<String, TextEditingController> _textControllers = {};
  
  @override
  void initState() {
    super.initState();
    // Initialize formData with initialData if provided
    _formData = widget.initialData != null 
        ? Map<String, dynamic>.from(widget.initialData!) 
        : {};
  }
  
  @override
  void dispose() {
    // Clean up controllers
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: widget.formFields.map((field) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildFieldWidget(field),
        );
      }).toList(),
    );
  }

  Widget _buildFieldWidget(FormFieldModel field) {
    switch (field.type) {
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.date:
        return _buildDateField(field);
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.checkbox:
        return _buildCheckboxField(field);
      case FieldType.photo:
        return _buildPhotoField(field);
    }
  }

  Widget _buildTextField(FormFieldModel field) {
    // Create or reuse controller to preserve value
    if (!_textControllers.containsKey(field.label)) {
      // Use initialData if available
      final initialValue = _formData[field.label]?.toString() ?? '';
      _textControllers[field.label] = TextEditingController(
        text: initialValue,
      );
    }
    
    return TextFormField(
      controller: _textControllers[field.label],
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        return null;
      },
      onChanged: (value) {
        _formData[field.label] = value;
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
      },
    );
  }

  Widget _buildNumberField(FormFieldModel field) {
    // Create or reuse controller to preserve value
    if (!_textControllers.containsKey(field.label)) {
      // Use initialData if available
      final initialValue = _formData[field.label]?.toString() ?? '';
      _textControllers[field.label] = TextEditingController(
        text: initialValue,
      );
    }
    
    return TextFormField(
      controller: _textControllers[field.label],
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        if (value != null && value.isNotEmpty) {
          if (double.tryParse(value) == null) {
            return 'Please enter a valid number';
          }
        }
        return null;
      },
      onChanged: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? double.tryParse(value) ?? value
            : '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? double.tryParse(value) ?? value
            : '';
        widget.onSaved(_formData);
      },
    );
  }

  Widget _buildDateField(FormFieldModel field) {
    // Parse initial date if exists
    DateTime? selectedDate;
    if (_formData[field.label] != null && _formData[field.label] is String) {
      try {
        selectedDate = DateTime.parse(_formData[field.label]);
      } catch (e) {
        selectedDate = null;
      }
    }

    return FormField<DateTime>(
      initialValue: selectedDate,
      validator: (value) {
        if (field.required && value == null) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value?.toIso8601String() ?? '';
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<DateTime> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  state.didChange(date);
                  selectedDate = date;
                  _formData[field.label] = date.toIso8601String();
                  widget.onSaved(_formData);
                  widget.onChanged?.call();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: field.label + (field.required ? ' *' : ''),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                  errorText: state.errorText,
                ),
                child: Text(
                  state.value != null
                      ? '${state.value!.day}/${state.value!.month}/${state.value!.year}'
                      : 'Select date',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownField(FormFieldModel field) {
    // Get initial value
    final initialValue = _formData[field.label] as String?;
    
    return DropdownButtonFormField<String>(
      value: initialValue,
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
      ),
      items: field.options?.map((option) {
        return DropdownMenuItem(
          value: option,
          child: Text(option),
        );
      }).toList(),
      validator: (value) {
        if (field.required && value == null) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
      },
      onChanged: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
    );
  }

  Widget _buildCheckboxField(FormFieldModel field) {
    // Get initial value
    final initialValue = _formData[field.label] as bool? ?? false;

    return FormField<bool>(
      initialValue: initialValue,
      validator: (value) {
        if (field.required && value != true) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? false;
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<bool> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              title: Text(field.label + (field.required ? ' *' : '')),
              value: state.value,
              onChanged: (value) {
                state.didChange(value);
                // checkboxValue = value;
                _formData[field.label] = value ?? false;
                widget.onSaved(_formData);
                widget.onChanged?.call();
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  state.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoField(FormFieldModel field) {
    // Get initial photos if exists
    List<String> initialPhotos = [];
    if (_formData[field.label] is List) {
      initialPhotos = (_formData[field.label] as List)
          .map((e) => e.toString())
          .toList();
    }
    
    final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
    final maxPhotos = field.maxPhotos ?? 1;

    return FormField<List<String>>(
      initialValue: initialPhotos,
      validator: (value) {
        final photoCount = value?.length ?? 0;
        
        // Changed: Return null to not block form submission
        // Warning will be shown in UI but form can still be saved
        if (minPhotos > 0 && photoCount < minPhotos) {
          // Visual warning only, don't block
          return null;
        }
        
        if (photoCount > maxPhotos) {
          // This should still block as it's a hard limit
          return 'Maximum $maxPhotos photo${maxPhotos > 1 ? "s" : ""} allowed';
        }
        
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? [];
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<List<String>> state) {
        return PhotoFieldWidget(
          label: field.label,
          required: field.required,
          minPhotos: minPhotos,
          maxPhotos: maxPhotos,
          initialPhotos: state.value,
          errorText: state.errorText,
          onChanged: (photos) {
            state.didChange(photos);
            // photoPaths = photos;
            _formData[field.label] = photos;
            widget.onSaved(_formData);
            widget.onChanged?.call();
          },
        );
      },
    );
  }
}
