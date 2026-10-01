import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/utils/field_values.dart';

/// Nilai isian per tipe field (SPEC §3.1/§3.3). Tabel kasus validasi sama
/// dengan server (gis-backend `mobile/tests_field_types.py`) dan web
/// (`fieldTypes.test.mjs`).

FormFieldModel _field(FieldType type,
        {List<String>? options, double? min, double? max, String? unit, bool required = false}) =>
    FormFieldModel(
        id: 'f',
        label: 'F',
        type: type,
        options: options,
        min: min,
        max: max,
        unit: unit,
        required: required);

const _opts = ['Ulat api', 'Tikus'];

void main() {
  group('validasi — tabel kasus bersama server/web', () {
    final cases = <(FormFieldModel, Object?, bool)>[
      (_field(FieldType.time), '14:30', true),
      (_field(FieldType.time), '00:00', true),
      (_field(FieldType.time), '23:59:59', true),
      (_field(FieldType.time), '24:00', false),
      (_field(FieldType.time), '7:5', false),
      (_field(FieldType.time), '14.30', false),
      (_field(FieldType.datetime), '2026-10-01T07:15:00.000', true),
      (_field(FieldType.datetime), '2026-10-01T07:15', true),
      (_field(FieldType.datetime), '2026-10-01', false),
      (_field(FieldType.datetime), '2026-13-01T07:15', false),
      (_field(FieldType.datetime), 'besok pagi', false),
      (_field(FieldType.multiselect, options: _opts), 'Ulat api; Tikus', true),
      (_field(FieldType.multiselect, options: _opts), ' Tikus ', true),
      (_field(FieldType.multiselect, options: _opts), 'Tikus; Babi', false),
      (_field(FieldType.rating), 4, true),
      (_field(FieldType.rating), '4', true),
      (_field(FieldType.rating), 1, true),
      (_field(FieldType.rating), 5, true),
      (_field(FieldType.rating), 0, false),
      (_field(FieldType.rating), 6, false),
      (_field(FieldType.rating), 3.5, false),
      (_field(FieldType.rating), true, false),
      (_field(FieldType.rating), 'bagus', false),
      (_field(FieldType.decimal), 2.5, true),
      (_field(FieldType.decimal), '2.5', true),
      (_field(FieldType.decimal), 'dua', false),
      (_field(FieldType.number, min: 0, max: 200), 200, true),
      (_field(FieldType.number, min: 0, max: 200), 0, true),
      (_field(FieldType.number, min: 0, max: 200), 201, false),
      (_field(FieldType.decimal, min: 0.5), 0.4, false),
      (_field(FieldType.decimal, max: 10), '10.0', true),
      (_field(FieldType.textarea), 'baris 1\nbaris 2', true),
    ];
    for (final (field, value, valid) in cases) {
      test('${field.type.name} ${field.min ?? ''}-${field.max ?? ''} "$value" → '
          '${valid ? 'valid' : 'tidak valid'}', () {
        expect(fieldValueIssue(field, value) == null, valid,
            reason: fieldValueIssue(field, value));
      });
    }
  });

  group('pesan', () {
    test('rentang menyebut batas dan satuan', () {
      expect(fieldValueIssue(_field(FieldType.decimal, min: 0, max: 200, unit: 'cm'), 250),
          'must be between 0 and 200 cm');
      expect(fieldValueIssue(_field(FieldType.number, min: 10), 5), 'must be at least 10');
      expect(fieldValueIssue(_field(FieldType.number, max: 3), 5), 'must be at most 3');
    });

    test('pilihan ganda menyebut opsi asing; jam; skala; wajib', () {
      expect(fieldValueIssue(_field(FieldType.multiselect, options: ['A']), 'A; B; C'),
          'has options that are not in the list: B, C');
      expect(fieldValueIssue(_field(FieldType.time), '25:00'), 'is not a valid time');
      expect(fieldValueIssue(_field(FieldType.rating), 9), 'must be 1–5');
      expect(fieldValueIssue(_field(FieldType.multiselect, options: ['A'], required: true), ' ; '),
          'is required');
      for (final type in [FieldType.rating, FieldType.time, FieldType.datetime, FieldType.textarea]) {
        expect(fieldValueIssue(_field(type, required: true), null), 'is required');
        expect(fieldValueIssue(_field(type), null), isNull);
      }
    });
  });

  group('pilihan ganda', () {
    test('bagian: dipangkas, bagian kosong dibuang', () {
      expect(multiselectParts('A; B ;;C'), ['A', 'B', 'C']);
      expect(multiselectParts(''), isEmpty);
      expect(multiselectParts(null), isEmpty);
    });

    test('gabung mengikuti urutan opsi; nilai di luar daftar di akhir', () {
      expect(joinMultiselect(['Tikus', 'Ulat api'], _opts), 'Ulat api; Tikus');
      expect(joinMultiselect(['Lama', 'Tikus'], _opts), 'Tikus; Lama');
      expect(joinMultiselect(const [], _opts), '');
    });
  });

  group('waktu & tanggal-waktu', () {
    test('format penyimpanan', () {
      expect(formatTimeValue(7, 5), '07:05');
      expect(formatDateTimeValue(DateTime(2026, 10, 1, 7, 15, 42)),
          '2026-10-01T07:15:00.000');
    });

    test('parse', () {
      expect(parseTimeValue('14:30'), (hour: 14, minute: 30));
      expect(parseTimeValue('14:30:59'), (hour: 14, minute: 30));
      expect(parseTimeValue('24:00'), isNull);
      expect(parseDateTimeValue('2026-10-01T07:15:00.000'), DateTime(2026, 10, 1, 7, 15));
      expect(parseDateTimeValue('2026-10-01'), isNull);
    });
  });

  group('teks tampilan', () {
    test('per tipe', () {
      expect(displayFieldValue(_field(FieldType.checkbox), true), 'Yes');
      expect(displayFieldValue(_field(FieldType.checkbox), 'false'), 'No');
      expect(displayFieldValue(_field(FieldType.rating), 4), '4 / 5');
      expect(displayFieldValue(_field(FieldType.decimal, unit: 'cm'), 35.5), '35.5 cm');
      expect(displayFieldValue(_field(FieldType.number), 10.0), '10');
      expect(displayFieldValue(_field(FieldType.datetime), '2026-10-01T07:15:00.000'),
          '2026-10-01 07:15');
      expect(displayFieldValue(_field(FieldType.date), '2026-10-01T00:00:00.000'), '2026-10-01');
      expect(displayFieldValue(_field(FieldType.multiselect, options: _opts), 'Tikus ;Ulat api'),
          'Tikus; Ulat api');
      expect(displayFieldValue(_field(FieldType.photo), [{}, {}]), '2 photo(s)');
      expect(displayFieldValue(_field(FieldType.text), null), '');
    });

    test('nilai tak sesuai format tampil apa adanya', () {
      expect(displayFieldValue(_field(FieldType.datetime), 'besok'), 'besok');
      expect(displayFieldValue(_field(FieldType.rating), 'bagus'), 'bagus');
    });
  });
}
