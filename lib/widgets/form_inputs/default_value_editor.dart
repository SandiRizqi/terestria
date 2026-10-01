import 'package:flutter/material.dart';

import '../../models/form_field_model.dart';
import '../../utils/field_values.dart';
import 'multi_choice_input.dart';

/// Isian nilai default sebuah field di builder (SPEC §3.4); bentuknya
/// mengikuti [type]. Melaporkan nilai mentah lewat [onChanged] (mis. `now`,
/// `35,5`, `"A; B"`); builder yang menormalkan saat simpan. Beri `key` per
/// tipe agar isian kosong lagi saat tipe diganti. Tidak untuk tipe foto.
class DefaultValueEditor extends StatefulWidget {
  final FieldType type;

  /// Opsi dropdown/pilihan ganda saat ini (tanpa duplikat).
  final List<String> options;
  final String? initialValue;
  final ValueChanged<String?> onChanged;

  /// Pesan error untuk nilai mentah, atau null bila valid.
  final String? Function(String? value) validator;

  const DefaultValueEditor({
    super.key,
    required this.type,
    required this.options,
    required this.initialValue,
    required this.onChanged,
    required this.validator,
  });

  @override
  State<DefaultValueEditor> createState() => _DefaultValueEditorState();
}

class _DefaultValueEditorState extends State<DefaultValueEditor> {
  final _text = TextEditingController();
  bool _now = false;
  String? _choice;

  bool get _isDateLike =>
      widget.type == FieldType.date ||
      widget.type == FieldType.time ||
      widget.type == FieldType.datetime;

  bool get _isChoice =>
      widget.type == FieldType.dropdown ||
      widget.type == FieldType.multiselect ||
      widget.type == FieldType.checkbox ||
      widget.type == FieldType.rating;

  /// Input tanpa label sendiri (bukan field ber-dekorasi).
  bool get _needsCaption => widget.type == FieldType.multiselect;

  String? get _value {
    if (_isChoice) return _choice;
    if (_isDateLike && _now) return defaultNowToken;
    return _text.text.isEmpty ? null : _text.text;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    if (initial == null) return;
    if (_isChoice) {
      _choice = initial;
    } else if (_isDateLike && initial.trim().toLowerCase() == defaultNowToken) {
      _now = true;
    } else {
      // Tanggal/tanggal-jam tersimpan ISO → tampil `YYYY-MM-DD [HH:mm]`.
      _text.text = displayFieldValue(
          FormFieldModel(id: '', label: '', type: widget.type), initial);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _setChoice(String? value) {
    setState(() => _choice = value);
    widget.onChanged(value);
  }

  String? get _hint {
    switch (widget.type) {
      case FieldType.number:
      case FieldType.decimal:
        return 'e.g. 0';
      case FieldType.date:
        return 'YYYY-MM-DD';
      case FieldType.time:
        return 'HH:mm (24 h)';
      case FieldType.datetime:
        return 'YYYY-MM-DD HH:mm';
      default:
        return null;
    }
  }

  TextInputType get _keyboard {
    switch (widget.type) {
      case FieldType.number:
      case FieldType.decimal:
        return const TextInputType.numberWithOptions(
            signed: true, decimal: true);
      case FieldType.date:
      case FieldType.time:
      case FieldType.datetime:
        return TextInputType.datetime;
      case FieldType.textarea:
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  Widget _dropdown(Map<String?, String> items) {
    // Nilai lama yang tak ada lagi di daftar tetap tampil (ditandai) —
    // DropdownButton melempar assert bila value tak ada di items.
    final stale = _choice != null && !items.containsKey(_choice);
    return DropdownButtonFormField<String?>(
      initialValue: _choice,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Default value',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
        if (stale)
          DropdownMenuItem(
            value: _choice,
            child: Text('$_choice (not in options)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.orange.shade800)),
          ),
      ],
      onChanged: _setChoice,
    );
  }

  Widget _input() {
    switch (widget.type) {
      case FieldType.dropdown:
        return _dropdown({
          null: 'No default',
          for (final option in widget.options) option: option,
        });
      case FieldType.checkbox:
        return _dropdown(
            const {null: 'No default', 'true': 'Checked', 'false': 'Unchecked'});
      case FieldType.multiselect:
        return MultiChoiceInput(
          options: widget.options,
          value: _choice,
          onChanged: (value) => _setChoice(value.isEmpty ? null : value),
        );
      case FieldType.rating:
        // Dropdown, bukan bintang: lima bintang 48 dp tak muat di dialog.
        return _dropdown({
          null: 'No default',
          for (var i = 1; i <= 5; i++) '$i': '$i / 5',
        });
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDateLike)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.type == FieldType.date
                    ? 'Use the date the form opens'
                    : 'Use the time the form opens'),
                value: _now,
                onChanged: (on) {
                  setState(() => _now = on ?? false);
                  widget.onChanged(_value);
                },
              ),
            if (!_now)
              TextFormField(
                controller: _text,
                keyboardType: _keyboard,
                minLines: 1,
                maxLines: widget.type == FieldType.textarea ? 3 : 1,
                decoration: InputDecoration(
                  labelText: 'Default value',
                  hintText: _hint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => widget.onChanged(_value),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<void>(
      validator: (_) => widget.validator(_value),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_needsCaption)
            Text('Default value',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          _input(),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              state.errorText ?? 'Filled in on new records; can be changed.',
              style: TextStyle(
                fontSize: 12,
                color: state.hasError
                    ? Theme.of(context).colorScheme.error
                    : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
