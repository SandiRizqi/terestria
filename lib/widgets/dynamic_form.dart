import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';
import '../models/geo_data_model.dart';
import '../services/pinned_values_service.dart';
import 'photo_field_widget.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide GeoPoint;

// ── Enum untuk 3 mode case pada text field ──
enum TextCaseMode { normal, upper, lower }

class DynamicForm extends StatefulWidget {
  final List<FormFieldModel> formFields;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback? onChanged;
  final Map<String, dynamic>? initialData;

  /// projectId diperlukan untuk fitur pin value
  final String? projectId;

  /// Watermark info — forwarded to PhotoFieldWidget
  final String? username;
  final double? latitude;
  final double? longitude;

  /// Posisi terkini saat foto diambil (watermark). Diutamakan daripada
  /// [latitude]/[longitude] yang hanya snapshot saat form dibuka.
  final GeoPoint? Function()? locationProvider;

  /// Untuk menggulir ke field bermasalah dari luar form.
  final DynamicFormController? controller;

  const DynamicForm({
    Key? key,
    required this.formFields,
    required this.onSaved,
    this.onChanged,
    this.initialData,
    this.projectId,
    this.username,
    this.latitude,
    this.longitude,
    this.locationProvider,
    this.controller,
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
  final Map<String, GlobalKey> _fieldKeys = {};

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
    widget.controller?._state = this;
    _loadPinnedValues();
    _loadCaseModes();
  }

  @override
  void didUpdateWidget(DynamicForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  /// Gulir sehingga field [label] terlihat. False bila field tak ditemukan.
  bool _scrollTo(String label) {
    final ctx = _fieldKeys[label]?.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300), alignment: 0.1);
    return true;
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

      // Pre-fill formData dengan pinned values. Nilai pin SELALU menang:
      // field ter-pin read-only & menampilkan nilai pin, jadi yang disimpan
      // harus sama dengan yang terlihat.
      for (final entry in values.entries) {
        _formData[entry.key] = entry.value;
        // Sync controller teks jika sudah dibuat
        final ctrl = _textControllers[entry.key];
        if (ctrl != null) {
          ctrl.text = entry.value?.toString() ?? '';
        }
      }
    });

    widget.onSaved(_formData);
    // Nilai pin bisa langsung memenuhi field wajib → minta induk menghitung
    // ulang validitas (dulu tombol Simpan tetap nonaktif sampai ada perubahan).
    widget.onChanged?.call();
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
    if (widget.controller?._state == this) widget.controller?._state = null;
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
          key: _fieldKeys.putIfAbsent(field.label, () => GlobalKey()),
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
      case FieldType.decimal:
        return _buildDecimalField(field);
      case FieldType.date:
        return _buildDateField(field);
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.checkbox:
        return _buildCheckboxField(field);
      case FieldType.photo:
        return _buildPhotoField(field);
      // Tipe yang input khususnya belum ada: sementara seperti teks.
      case FieldType.textarea:
      case FieldType.multiselect:
      case FieldType.time:
      case FieldType.datetime:
      case FieldType.rating:
        return _buildTextField(field);
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
          tooltip: 'As typed',
          active: currentMode == TextCaseMode.normal,
          isFirst: true,
          isLast: false,
          onTap: () => _setCaseMode(fieldLabel, TextCaseMode.normal),
        ),
        _CaseSegment(
          label: 'ABC',
          tooltip: 'ALL CAPS',
          active: currentMode == TextCaseMode.upper,
          isFirst: false,
          isLast: false,
          onTap: () => _setCaseMode(fieldLabel, TextCaseMode.upper),
        ),
        _CaseSegment(
          label: 'abc',
          tooltip: 'all lowercase',
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
      // Koma & titik diterima (keyboard lokal Indonesia memakai koma) dan
      // tanda minus boleh; disimpan sebagai angka dengan titik desimal.
      keyboardType:
          const TextInputType.numberWithOptions(signed: true, decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d{0,2}')),
      ],
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        if (value != null && value.isNotEmpty) {
          if (parseLocaleNumber(value) == null) {
            return 'Please enter a valid number';
          }
        }
        return null;
      },
      onChanged: (value) {
        _formData[field.label] = value.isNotEmpty
            ? parseLocaleNumber(value) ?? value
            : '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? parseLocaleNumber(value) ?? value
            : '';
        widget.onSaved(_formData);
      },
    );
  }

  // ════════════════════════════════════════════════════════
  // DECIMAL FIELD – dengan pin
  // ════════════════════════════════════════════════════════
  Widget _buildDecimalField(FormFieldModel field) {
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
                borderSide: BorderSide(color: Colors.amber.shade300, width: 1.5),
              )
            : const OutlineInputBorder(),
        enabledBorder: pinned
            ? OutlineInputBorder(
                borderSide: BorderSide(color: Colors.amber.shade300, width: 1.5),
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
                      color: pinned ? Colors.amber.shade700 : Colors.grey.shade400,
                    ),
                  ),
                ),
              )
            : null,
      ),
      keyboardType:
          const TextInputType.numberWithOptions(signed: true, decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*')),
      ],
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        if (value != null && value.isNotEmpty) {
          if (parseLocaleNumber(value) == null) {
            return 'Please enter a valid decimal number';
          }
        }
        return null;
      },
      onChanged: (String value) {
        _formData[field.label] = value.isNotEmpty
            ? parseLocaleNumber(value) ?? value
            : '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? parseLocaleNumber(value) ?? value
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
                        TextButton(
                          onPressed: () {
                            final now = DateTime.now();
                            final today =
                                DateTime(now.year, now.month, now.day);
                            state.didChange(today);
                            selectedDate = today;
                            _formData[field.label] = today.toIso8601String();
                            widget.onSaved(_formData);
                            widget.onChanged?.call();
                          },
                          child: const Text('Today'),
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
    final pinnedVal = _pinnedValues[field.label]?.toString();
    final initVal = _formData[field.label]?.toString();
    final rawVal = pinnedVal ?? initVal;
    final currentVal = (rawVal == null || rawVal.isEmpty) ? null : rawVal;

    // Sync formData
    if (currentVal != null && _formData[field.label] == null) {
      _formData[field.label] = currentVal;
    }

    // Nilai lama yang tak lagi ada di opsi (opsi project diubah) tetap
    // ditampilkan & dipertahankan — DropdownButton melempar assert bila
    // value tak ada di items.
    final options = <String>[...?field.options];
    final staleValue = currentVal != null && !options.contains(currentVal);

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
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
                if (staleValue)
                  DropdownMenuItem(
                    value: currentVal,
                    child: Text('$currentVal (not in list)',
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
              ],
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
    final raw = pinnedVal ?? initVal;
    // Server bisa mengirim "true"/1 — jangan cast langsung ke bool.
    final startVal = raw is bool
        ? raw
        : (raw != null &&
            (raw.toString().toLowerCase() == 'true' || raw.toString() == '1'));

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
          // Watermark info forwarded from DataCollectionScreen
          username: widget.username,
          latitude: widget.latitude,
          longitude: widget.longitude,
          locationProvider: widget.locationProvider,
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

// ════════════════════════════════════════════════════════
// Validasi & helper bersama (form koleksi, form atribut tracking)
// ════════════════════════════════════════════════════════

/// Angka dari input user: menerima koma atau titik desimal (keyboard lokal
/// Indonesia memakai koma) dan tanda minus. Null bila bukan angka.
double? parseLocaleNumber(String input) {
  final s = input.trim().replaceAll(',', '.');
  if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
  return double.tryParse(s);
}

/// Pengendali [DynamicForm] dari luar (mis. menggulir ke field bermasalah).
class DynamicFormController {
  _DynamicFormState? _state;

  /// Gulir sehingga field [label] terlihat. False bila tak ditemukan.
  bool scrollTo(String label) => _state?._scrollTo(label) ?? false;
}

/// Masalah pada satu field (wajib kosong, jumlah foto tak sesuai, dsb.).
class FieldIssue {
  final FormFieldModel field;
  final String message;
  const FieldIssue(this.field, this.message);
}

bool _isBlank(Object? v) =>
    v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

/// Field yang belum memenuhi syarat, urut sesuai form. Aturan sama dengan
/// validator tiap field — dipakai untuk memblokir simpan (dulu data tetap
/// tersimpan walau field wajib kosong) dan untuk indikator progres.
List<FieldIssue> formFieldIssues(
    List<FormFieldModel> fields, Map<String, dynamic> data) {
  final issues = <FieldIssue>[];
  for (final field in fields) {
    final value = data[field.label];
    switch (field.type) {
      case FieldType.photo:
        final count = value is List ? value.length : (_isBlank(value) ? 0 : 1);
        final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
        final maxPhotos = field.maxPhotos ?? 1;
        if (count < minPhotos) {
          issues.add(FieldIssue(
              field,
              minPhotos == 1
                  ? 'needs a photo'
                  : 'needs at least $minPhotos photos'));
        } else if (count > maxPhotos) {
          issues.add(FieldIssue(field, 'allows at most $maxPhotos photo(s)'));
        }
        break;
      case FieldType.checkbox:
        final checked = value == true ||
            value?.toString().toLowerCase() == 'true' ||
            value?.toString() == '1';
        if (field.required && !checked) {
          issues.add(FieldIssue(field, 'must be checked'));
        }
        break;
      case FieldType.number:
      case FieldType.decimal:
        if (_isBlank(value)) {
          if (field.required) issues.add(FieldIssue(field, 'is required'));
        } else if (value is! num && parseLocaleNumber(value.toString()) == null) {
          issues.add(FieldIssue(field, 'is not a valid number'));
        }
        break;
      case FieldType.text:
      case FieldType.date:
      case FieldType.dropdown:
      case FieldType.textarea:
      case FieldType.multiselect:
      case FieldType.time:
      case FieldType.datetime:
      case FieldType.rating:
        if (field.required && _isBlank(value)) {
          issues.add(FieldIssue(field, 'is required'));
        }
        break;
    }
  }
  return issues;
}

/// Ringkasan "3 of 5 required fields completed" + bar progres.
class RequiredFieldsProgress extends StatelessWidget {
  final List<FormFieldModel> fields;
  final Map<String, dynamic> data;

  const RequiredFieldsProgress(
      {super.key, required this.fields, required this.data});

  @override
  Widget build(BuildContext context) {
    final required = fields.where((f) =>
        f.required || (f.type == FieldType.photo && (f.minPhotos ?? 0) > 0));
    final total = required.length;
    if (total == 0) return const SizedBox.shrink();
    final pending = formFieldIssues(required.toList(), data).length;
    final done = total - pending;
    final complete = pending == 0;
    final color = complete ? Colors.green.shade700 : Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(complete ? Icons.check_circle : Icons.pending_actions,
                  size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                complete
                    ? 'All required fields completed'
                    : '$done of $total required fields completed',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : done / total,
              minHeight: 6,
              color: color,
              backgroundColor: color.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}
