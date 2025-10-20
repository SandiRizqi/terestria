import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';
import 'photo_field_widget.dart';

class DynamicForm extends StatefulWidget {
  final List<FormFieldModel> formFields;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback? onChanged;

  const DynamicForm({
    Key? key,
    required this.formFields,
    required this.onSaved,
    this.onChanged,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final Map<String, dynamic> _formData = {};

  @override
  Widget build(BuildContext context) {
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
    return TextFormField(
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
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
      },
    );
  }

  Widget _buildNumberField(FormFieldModel field) {
    return TextFormField(
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
    DateTime? selectedDate;

    return FormField<DateTime>(
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
    return DropdownButtonFormField<String>(
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
        widget.onChanged?.call();
      },
    );
  }

  Widget _buildCheckboxField(FormFieldModel field) {
    bool? checkboxValue = false;

    return FormField<bool>(
      initialValue: false,
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
                checkboxValue = value;
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
    List<String> photoPaths = [];
    final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
    final maxPhotos = field.maxPhotos ?? 1;

    return FormField<List<String>>(
      initialValue: [],
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
            photoPaths = photos;
            widget.onChanged?.call();
          },
        );
      },
    );
  }
}
