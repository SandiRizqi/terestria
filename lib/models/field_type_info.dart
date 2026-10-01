import 'package:flutter/material.dart';

import 'form_field_model.dart';

/// Nama, ikon, dan deskripsi tiap tipe field — satu sumber untuk pembuat
/// form, layar pembuat project, dan detail project.
class FieldTypeInfo {
  final FieldType type;
  final String label;
  final IconData icon;
  final String description;

  const FieldTypeInfo(this.type, this.label, this.icon, this.description);
}

/// Urutan = urutan tampil di pembuat form.
const List<FieldTypeInfo> fieldTypeInfos = [
  FieldTypeInfo(FieldType.text, 'Text', Icons.text_fields, 'Short text, one line'),
  FieldTypeInfo(FieldType.textarea, 'Long text', Icons.notes,
      'Notes over several lines'),
  FieldTypeInfo(FieldType.number, 'Number', Icons.numbers, 'Whole number'),
  FieldTypeInfo(FieldType.decimal, 'Decimal', Icons.straighten,
      'Number with decimals'),
  FieldTypeInfo(FieldType.date, 'Date', Icons.calendar_today, 'A date'),
  FieldTypeInfo(FieldType.time, 'Time', Icons.schedule, 'Time of day (24 h)'),
  FieldTypeInfo(FieldType.datetime, 'Date & time', Icons.event,
      'A date with a time'),
  FieldTypeInfo(FieldType.dropdown, 'Dropdown', Icons.arrow_drop_down_circle,
      'One choice from a list'),
  FieldTypeInfo(FieldType.multiselect, 'Multiple choice', Icons.checklist,
      'Several choices from a list'),
  FieldTypeInfo(FieldType.checkbox, 'Checkbox', Icons.check_box, 'Yes or no'),
  FieldTypeInfo(FieldType.rating, 'Rating (1–5)', Icons.star_outline,
      'A score from 1 to 5'),
  FieldTypeInfo(FieldType.photo, 'Photo', Icons.photo_camera, 'Camera photos'),
];

FieldTypeInfo fieldTypeInfo(FieldType type) =>
    fieldTypeInfos.firstWhere((info) => info.type == type);

/// Nama tipe untuk ditampilkan; tipe tak dikenal menyebut nama aslinya.
String fieldTypeDisplayName(FormFieldModel field) => field.isUnknownType
    ? '${field.unknownTypeName} (not supported in this app version)'
    : fieldTypeInfo(field.type).label;
