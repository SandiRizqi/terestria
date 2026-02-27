import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';
import '../services/pinned_values_service.dart';
import 'photo_field_widget.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ── Enum untuk 3 mode case pada text field ──
enum TextCaseMode { normal, upper, lower }

class DynamicForm extends StatefulWidget {
  final List<FormFieldModel> formFields;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback? onChanged;
  final Map<String, dynamic>? initialData;

  /// projectId diperlukan untuk fitur pin value
  final String? projectId;

  const DynamicForm({
    Key? key,
    required this.formFields,
    required this.onSaved,
    this.onChanged,
    this.initialData,
    this.projectId,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Map<String, dynamic> _formData;
  final Map<String, TextEditingController> _textControllers = {};

  // ── Case mode per text field ──
  final Map<String, TextCaseMode> _caseModes = {};
  bool _caseModesLoaded = false;

  // ── Pin state ──
  final PinnedValuesService _pinnedValuesService = PinnedValuesService();
  Map<String, bool> _pinnedFields = {};   // fieldLabel → isPinned
  Map<String, dynamic> _pinnedValues = {}; // fieldLabel → value
  bool _pinnedLoaded = false;

  @override
  void initState() {
    super.initState();
    _formData = widget.initialData != null
        ? Map<String, dynamic>.from(widget.initialData!)
        : {};
    _loadPinnedValues();
    _loadCaseModes();
  }

  Future<void> _loadCaseModes() async {
    if (widget.projectId == null) {
      setState(() => _caseModesLoaded = true);
      return;
    }
    final saved =
        await _pinnedValuesService.loadCaseModes(widget.projectId!);
    if (!mounted) return;
    setState(() {
      for (final entry in saved.entries) {
        _caseModes[entry.key] = _modeFromString(entry.value);
      }
      _caseModesLoaded = true;
    });
  }

  TextCaseMode _modeFromString(String s) {
    switch (s) {
      case 'upper':
        return TextCaseMode.upper;
      case 'lower':
        return TextCaseMode.lower;
      default:
        return TextCaseMode.normal;
    }
  }

  String _modeToString(TextCaseMode mode) {
    switch (mode) {
      case TextCaseMode.upper:
        return 'upper';
      case TextCaseMode.lower:
        return 'lower';
      case TextCaseMode.normal:
        return 'normal';
    }
  }

  Future<void> _loadPinnedValues() async {
    if (widget.projectId == null) {
      setState(() => _pinnedLoaded = true);
      return;
    }
    final values =
        await _pinnedValuesService.loadPinnedValues(widget.projectId!);
    if (!mounted) return;

    final pinned = <String, bool>{};
    for (final label in values.keys) {
      pinned[label] = true;
    }

    setState(() {
      _pinnedValues = values;
      _pinnedFields = pinned;
      _pinnedLoaded = true;

      // Pre-fill formData dengan pinned values
      for (final entry in values.entries) {
        // Hanya isi jika belum ada nilai dari initialData
        if (_formData[entry.key] == null) {
          _formData[entry.key] = entry.value;
        }
        // Sync controller teks jika sudah dibuat
        final ctrl = _textControllers[entry.key];
        if (ctrl != null) {
          ctrl.text = entry.value?.toString() ?? '';
        }
      }
    });

    widget.onSaved(_formData);
  }

  Future<void> _togglePin(String fieldLabel) async {
    if (widget.projectId == null) return;

    final isPinned = _pinnedFields[fieldLabel] == true;

    if (isPinned) {
      // UNPIN
      await _pinnedValuesService.removePinnedValue(
          widget.projectId!, fieldLabel);
      setState(() {
        _pinnedFields[fieldLabel] = false;
        _pinnedValues.remove(fieldLabel);
      });
    } else {
      // PIN – simpan nilai saat ini
      final currentValue = _formData[fieldLabel];
      await _pinnedValuesService.savePinnedValue(
          widget.projectId!, fieldLabel, currentValue);
      setState(() {
        _pinnedFields[fieldLabel] = true;
        _pinnedValues[fieldLabel] = currentValue;
      });
    }
  }

  bool _isPinned(String fieldLabel) => _pinnedFields[fieldLabel] == true;

  @override
  void dispose() {
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _scanQRCode(FormFieldModel field) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _QRScannerScreen(fieldLabel: field.label),
      ),
    );

    if (result != null && result.isNotEmpty) {
      final converted = _applyCase(field.label, result);
      _textControllers[field.label]?.text = converted;
      _formData[field.label] = converted;
      widget.onSaved(_formData);
      widget.onChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR Code scanned: $converted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Terapkan case mode pada string
  String _applyCase(String fieldLabel, String value) {
    switch (_caseModes[fieldLabel] ?? TextCaseMode.normal) {
      case TextCaseMode.upper:
        return value.toUpperCase();
      case TextCaseMode.lower:
        return value.toLowerCase();
      case TextCaseMode.normal:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_pinnedLoaded || !_caseModesLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

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

  // ════════════════════════════════════════════════════════
  // TEXT FIELD – dengan toggle case + pin
  // ════════════════════════════════════════════════════════
  Widget _buildTextField(FormFieldModel field) {
    if (!_textControllers.containsKey(field.label)) {
      // Prioritas: pinnedValue → initialData → kosong
      final pinVal = _pinnedValues[field.label]?.toString();
      final initVal = _formData[field.label]?.toString() ?? '';
      final startVal = pinVal ?? initVal;
      _textControllers[field.label] = TextEditingController(text: startVal);
      if (_formData[field.label] == null && startVal.isNotEmpty) {
        _formData[field.label] = startVal;
      }
    }

    final pinned = _isPinned(field.label);
    final mode = _caseModes[field.label] ?? TextCaseMode.normal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _textControllers[field.label],
          readOnly: pinned,
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            border: pinned
                ? OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Colors.amber.shade300,
                        width: 1.5,
                        style: BorderStyle.solid),
                  )
                : const OutlineInputBorder(),
            enabledBorder: pinned
                ? OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Colors.amber.shade300, width: 1.5),
                  )
                : null,
            filled: pinned,
            fillColor: pinned ? Colors.amber.shade50 : null,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pin button
                if (widget.projectId != null)
                  GestureDetector(
                    onTap: () => _togglePin(field.label),
                    child: Tooltip(
                      message: pinned ? 'Unpin value' : 'Pin value',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          pinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 20,
                          color: pinned
                              ? Colors.amber.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                // QR Scan button (disabled kalau pinned)
                if (!pinned)
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan QR Code',
                    onPressed: () => _scanQRCode(field),
                  ),
              ],
            ),
          ),
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) {
            // Terapkan case mode saat mengetik
            final converted = _applyCase(field.label, value);
            if (converted != value) {
              final ctrl = _textControllers[field.label]!;
              final selection = ctrl.selection;
              ctrl.value = ctrl.value.copyWith(
                text: converted,
                selection: selection.copyWith(
                  baseOffset:
                      selection.baseOffset.clamp(0, converted.length),
                  extentOffset:
                      selection.extentOffset.clamp(0, converted.length),
                ),
              );
              _formData[field.label] = converted;
            } else {
              _formData[field.label] = value;
            }
            widget.onSaved(_formData);
            widget.onChanged?.call();
          },
          onSaved: (value) {
            _formData[field.label] = value ?? '';
            widget.onSaved(_formData);
          },
        ),

        // ── Toggle Case Row ──
        if (!pinned) ...[
          const SizedBox(height: 6),
          _buildCaseToggle(field.label, mode),
        ],
      ],
    );
  }

  /// 3-segmented toggle: Aa | ABC | abc
  Widget _buildCaseToggle(String fieldLabel, TextCaseMode currentMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 2),
        _CaseSegment(
          label: 'Aa',
          tooltip: 'Normal (apa adanya)',
          active: currentMode == TextCaseMode.normal,
          isFirst: true,
          isLast: false,
          onTap: () => _setCaseMode(fieldLabel, TextCaseMode.normal),
        ),
        _CaseSegment(
          label: 'ABC',
          tooltip: 'Uppercase semua',
          active: currentMode == TextCaseMode.upper,
          isFirst: false,
          isLast: false,
          onTap: () => _setCaseMode(fieldLabel, TextCaseMode.upper),
        ),
        _CaseSegment(
          label: 'abc',
          tooltip: 'Lowercase semua',
          active: currentMode == TextCaseMode.lower,
          isFirst: false,
          isLast: true,
          onTap: () => _setCaseMode(fieldLabel, TextCaseMode.lower),
        ),
      ],
    );
  }

  void _setCaseMode(String fieldLabel, TextCaseMode mode) {
    setState(() => _caseModes[fieldLabel] = mode);

    // Simpan ke storage agar persist untuk project yang sama
    if (widget.projectId != null) {
      if (mode == TextCaseMode.normal) {
        // Mode normal = hapus dari storage (tidak perlu disimpan)
        _pinnedValuesService.removeCaseMode(widget.projectId!, fieldLabel);
      } else {
        _pinnedValuesService.saveCaseMode(
            widget.projectId!, fieldLabel, _modeToString(mode));
      }
    }

    // Konversi teks yang sudah ada
    final ctrl = _textControllers[fieldLabel];
    if (ctrl != null && ctrl.text.isNotEmpty) {
      String converted;
      switch (mode) {
        case TextCaseMode.upper:
          converted = ctrl.text.toUpperCase();
          break;
        case TextCaseMode.lower:
          converted = ctrl.text.toLowerCase();
          break;
        case TextCaseMode.normal:
          converted = ctrl.text; // tidak diubah
          break;
      }
      if (converted != ctrl.text) {
        final sel = ctrl.selection;
        ctrl.value = ctrl.value.copyWith(
          text: converted,
          selection: sel.copyWith(
            baseOffset: sel.baseOffset.clamp(0, converted.length),
            extentOffset: sel.extentOffset.clamp(0, converted.length),
          ),
        );
        _formData[fieldLabel] = converted;
        widget.onSaved(_formData);
        widget.onChanged?.call();
      }
    }
  }

  // ════════════════════════════════════════════════════════
  // NUMBER FIELD – dengan pin
  // ════════════════════════════════════════════════════════
  Widget _buildNumberField(FormFieldModel field) {
    if (!_textControllers.containsKey(field.label)) {
      final pinVal = _pinnedValues[field.label]?.toString();
      final initVal = _formData[field.label]?.toString() ?? '';
      final startVal = pinVal ?? initVal;
      _textControllers[field.label] = TextEditingController(text: startVal);
      if (_formData[field.label] == null && startVal.isNotEmpty) {
        _formData[field.label] = startVal;
      }
    }

    final pinned = _isPinned(field.label);

    return TextFormField(
      controller: _textControllers[field.label],
      readOnly: pinned,
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: pinned
            ? OutlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.amber.shade300, width: 1.5),
              )
            : const OutlineInputBorder(),
        enabledBorder: pinned
            ? OutlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.amber.shade300, width: 1.5),
              )
            : null,
        filled: pinned,
        fillColor: pinned ? Colors.amber.shade50 : null,
        suffixIcon: widget.projectId != null
            ? GestureDetector(
                onTap: () => _togglePin(field.label),
                child: Tooltip(
                  message: pinned ? 'Unpin value' : 'Pin value',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20,
                      color: pinned
                          ? Colors.amber.shade700
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              )
            : null,
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

  // ════════════════════════════════════════════════════════
  // DATE FIELD – dengan pin
  // ════════════════════════════════════════════════════════
  Widget _buildDateField(FormFieldModel field) {
    DateTime? selectedDate;
    final pinnedRaw = _pinnedValues[field.label];
    final rawVal = pinnedRaw ?? _formData[field.label];

    if (rawVal != null && rawVal is String && rawVal.isNotEmpty) {
      try {
        selectedDate = DateTime.parse(rawVal);
        _formData[field.label] ??= rawVal;
      } catch (_) {}
    }

    final pinned = _isPinned(field.label);

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
              onTap: pinned
                  ? null
                  : () async {
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
                  border: pinned
                      ? OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.amber.shade300, width: 1.5),
                        )
                      : const OutlineInputBorder(),
                  enabledBorder: pinned
                      ? OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.amber.shade300, width: 1.5),
                        )
                      : null,
                  filled: pinned,
                  fillColor: pinned ? Colors.amber.shade50 : null,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.projectId != null)
                        GestureDetector(
                          onTap: () => _togglePin(field.label),
                          child: Tooltip(
                            message: pinned ? 'Unpin value' : 'Pin value',
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 20,
                                color: pinned
                                    ? Colors.amber.shade700
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      if (!pinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.calendar_today),
                        ),
                    ],
                  ),
                  errorText: state.errorText,
                ),
                child: Text(
                  state.value != null
                      ? '${state.value!.day}/${state.value!.month}/${state.value!.year}'
                      : 'Select date',
                  style: TextStyle(
                    color: pinned ? Colors.black87 : null,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════
  // DROPDOWN FIELD – dengan pin
  // ════════════════════════════════════════════════════════
  Widget _buildDropdownField(FormFieldModel field) {
    final pinned = _isPinned(field.label);
    final pinnedVal = _pinnedValues[field.label] as String?;
    final initVal = _formData[field.label] as String?;
    final currentVal = pinnedVal ?? initVal;

    // Sync formData
    if (currentVal != null && _formData[field.label] == null) {
      _formData[field.label] = currentVal;
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: pinned
            ? OutlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.amber.shade300, width: 1.5),
              )
            : const OutlineInputBorder(),
        enabledBorder: pinned
            ? OutlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.amber.shade300, width: 1.5),
              )
            : null,
        filled: pinned,
        fillColor: pinned ? Colors.amber.shade50 : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        suffixIcon: widget.projectId != null
            ? GestureDetector(
                onTap: () => _togglePin(field.label),
                child: Tooltip(
                  message: pinned ? 'Unpin value' : 'Pin value',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20,
                      color: pinned
                          ? Colors.amber.shade700
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              )
            : null,
      ),
      child: pinned
          // Kalau pinned: tampilkan nilai saja, tidak bisa diubah
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                currentVal ?? '',
                style: const TextStyle(fontSize: 16),
              ),
            )
          : DropdownButtonFormField<String>(
              value: currentVal,
              decoration: const InputDecoration.collapsed(hintText: ''),
              items: field.options?.map((option) {
                return DropdownMenuItem(value: option, child: Text(option));
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
            ),
    );
  }

  // ════════════════════════════════════════════════════════
  // CHECKBOX FIELD – dengan pin
  // ════════════════════════════════════════════════════════
  Widget _buildCheckboxField(FormFieldModel field) {
    final pinned = _isPinned(field.label);
    final pinnedVal = _pinnedValues[field.label];
    final initVal = _formData[field.label];
    final startVal = (pinnedVal ?? initVal) as bool? ?? false;

    return FormField<bool>(
      initialValue: startVal,
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
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    title: Text(field.label + (field.required ? ' *' : '')),
                    value: state.value,
                    onChanged: pinned
                        ? null // read-only kalau pinned
                        : (value) {
                            state.didChange(value);
                            _formData[field.label] = value ?? false;
                            widget.onSaved(_formData);
                            widget.onChanged?.call();
                          },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor:
                        pinned ? Colors.amber.shade50 : null,
                    shape: pinned
                        ? RoundedRectangleBorder(
                            side: BorderSide(
                                color: Colors.amber.shade300, width: 1.5),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                  ),
                ),
                if (widget.projectId != null)
                  GestureDetector(
                    onTap: () => _togglePin(field.label),
                    child: Tooltip(
                      message: pinned ? 'Unpin value' : 'Pin value',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          pinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 20,
                          color: pinned
                              ? Colors.amber.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
              ],
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

  // ════════════════════════════════════════════════════════
  // PHOTO FIELD – tanpa pin (sesuai requirement)
  // ════════════════════════════════════════════════════════
  Widget _buildPhotoField(FormFieldModel field) {
    dynamic initialPhotos = _formData[field.label];
    final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
    final maxPhotos = field.maxPhotos ?? 1;

    return FormField<List<Map<String, dynamic>>>(
      initialValue: initialPhotos is List
          ? initialPhotos.cast<Map<String, dynamic>>()
          : [],
      validator: (value) {
        final photoCount = value?.length ?? 0;
        if (minPhotos > 0 && photoCount < minPhotos) {
          if (minPhotos == 1) return 'At least 1 photo is required';
          return 'At least $minPhotos photos required';
        }
        if (photoCount > maxPhotos) {
          return 'Maximum $maxPhotos photo${maxPhotos > 1 ? "s" : ""} allowed';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? [];
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<List<Map<String, dynamic>>> state) {
        return PhotoFieldWidget(
          label: field.label,
          required: field.required,
          minPhotos: minPhotos,
          maxPhotos: maxPhotos,
          initialPhotos: initialPhotos,
          errorText: state.errorText,
          onChanged: (photos) {
            state.didChange(photos);
            _formData[field.label] = photos;
            widget.onSaved(_formData);
            widget.onChanged?.call();
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════
// Widget helper: satu segmen tombol case
// ════════════════════════════════════════════════════════
class _CaseSegment extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _CaseSegment({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(6) : Radius.zero,
      right: isLast ? const Radius.circular(6) : Radius.zero,
    );

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? primary : Colors.grey.shade100,
            borderRadius: radius,
            border: Border.all(
              color: active ? primary : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  active ? FontWeight.w700 : FontWeight.w400,
              color: active ? Colors.white : Colors.grey.shade600,
              letterSpacing: label == 'ABC' ? 0.5 : 0,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// QR Scanner Screen
// ════════════════════════════════════════════════════════
class _QRScannerScreen extends StatefulWidget {
  final String fieldLabel;
  const _QRScannerScreen({required this.fieldLabel});

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  bool _isTorchOn = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final String? code = barcode.rawValue;

    if (code != null && code.isNotEmpty) {
      setState(() => _isProcessing = true);
      HapticFeedback.mediumImpact();
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan QR for "${widget.fieldLabel}"'),
        actions: [
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? Colors.yellow : null,
            ),
            onPressed: () async {
              await cameraController.toggleTorch();
              setState(() => _isTorchOn = !_isTorchOn);
            },
            tooltip: 'Toggle Flashlight',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),
          CustomPaint(
            painter: _ScannerOverlayPainter(),
            child: Container(),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Position the QR code within the frame',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.7;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    final Rect scanArea =
        Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(
              RRect.fromRectAndRadius(scanArea, const Radius.circular(12))),
      ),
      backgroundPaint,
    );

    final Paint cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const double cornerLength = 30;

    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top)
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize - cornerLength, top)
        ..lineTo(left + scanAreaSize, top)
        ..lineTo(left + scanAreaSize, top + cornerLength),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left, top + scanAreaSize - cornerLength)
        ..lineTo(left, top + scanAreaSize)
        ..lineTo(left + cornerLength, top + scanAreaSize),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize - cornerLength, top + scanAreaSize)
        ..lineTo(left + scanAreaSize, top + scanAreaSize)
        ..lineTo(left + scanAreaSize, top + scanAreaSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
