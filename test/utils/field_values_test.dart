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

    test('daftar di field teks digabung koma (mis. dari web)', () {
      expect(displayFieldValue(_field(FieldType.text), ['a', 'b']), 'a, b');
    });
  });

  group('filter daftar data', () {
    test('jenis filter per tipe', () {
      for (final t in [
        FieldType.text,
        FieldType.textarea,
        FieldType.number,
        FieldType.decimal,
        FieldType.time,
        FieldType.datetime,
      ]) {
        expect(fieldFilterKind(t), FieldFilterKind.text, reason: t.name);
      }
      expect(fieldFilterKind(FieldType.dropdown), FieldFilterKind.choice);
      expect(fieldFilterKind(FieldType.multiselect), FieldFilterKind.choice);
      expect(fieldFilterKind(FieldType.rating), FieldFilterKind.rating);
      expect(fieldFilterKind(FieldType.checkbox), FieldFilterKind.checkbox);
      expect(fieldFilterKind(FieldType.date), FieldFilterKind.date);
      expect(fieldFilterKind(FieldType.photo), FieldFilterKind.none);
    });

    test('filter kosong tidak menyaring', () {
      expect(fieldFilterMatches(_field(FieldType.text), 'x', null), isTrue);
      expect(fieldFilterMatches(_field(FieldType.text), 'x', '  '), isTrue);
      expect(fieldFilterMatches(_field(FieldType.rating), null, ''), isTrue);
    });

    test('teks panjang, waktu, tanggal-waktu: berisi teks (tak peka huruf)', () {
      final note = _field(FieldType.textarea);
      expect(fieldFilterMatches(note, 'Daun\nkuning di blok', 'KUNING'), isTrue);
      expect(fieldFilterMatches(note, 'Daun hijau', 'kuning'), isFalse);
      expect(fieldFilterMatches(note, null, 'nu'), isFalse,
          reason: 'kosong bukan teks "null"');

      expect(fieldFilterMatches(_field(FieldType.time), '07:15', '07'), isTrue);
      expect(fieldFilterMatches(_field(FieldType.time), '07:15', '08'), isFalse);

      // Cocok dengan nilai tersimpan maupun tampilan "2026-10-01 07:15".
      final dt = _field(FieldType.datetime);
      expect(fieldFilterMatches(dt, '2026-10-01T07:15:00.000', '2026-10-01 07'), isTrue);
      expect(fieldFilterMatches(dt, '2026-10-01T07:15:00.000', '2026-10-01T07'), isTrue);
      expect(fieldFilterMatches(dt, '2026-10-01T07:15:00.000', '2026-10-02'), isFalse);
    });

    test('angka: berisi teks pada nilai atau tampilan', () {
      final d = _field(FieldType.decimal, unit: 'cm');
      expect(fieldFilterMatches(d, 35.0, '35'), isTrue);
      expect(fieldFilterMatches(d, 35.5, '35.5 cm'), isTrue);
      expect(fieldFilterMatches(d, 12, '35'), isFalse);
    });

    test('pilihan ganda: record yang memuat opsi itu', () {
      final m = _field(FieldType.multiselect, options: _opts);
      expect(fieldFilterMatches(m, 'Ulat api; Tikus', 'Tikus'), isTrue);
      expect(fieldFilterMatches(m, ['Tikus'], 'Tikus'), isTrue);
      expect(fieldFilterMatches(m, 'Ulat api', 'Tikus'), isFalse);
      expect(fieldFilterMatches(m, 'Tikus besar', 'Tikus'), isFalse,
          reason: 'per opsi, bukan potongan teks');
      expect(fieldFilterMatches(m, null, 'Tikus'), isFalse);
    });

    test('dropdown: sama persis', () {
      final d = _field(FieldType.dropdown, options: _opts);
      expect(fieldFilterMatches(d, 'Tikus', 'Tikus'), isTrue);
      expect(fieldFilterMatches(d, 'Tikus besar', 'Tikus'), isFalse);
    });

    test('skala: nilai 1–5 sama (angka atau teks angka)', () {
      final r = _field(FieldType.rating);
      expect(fieldFilterMatches(r, 4, '4'), isTrue);
      expect(fieldFilterMatches(r, '4', '4'), isTrue);
      expect(fieldFilterMatches(r, 4.0, '4'), isTrue);
      expect(fieldFilterMatches(r, 3, '4'), isFalse);
      expect(fieldFilterMatches(r, null, '4'), isFalse);
    });

    test('checkbox: Yes/No', () {
      final c = _field(FieldType.checkbox);
      expect(fieldFilterMatches(c, true, 'true'), isTrue);
      expect(fieldFilterMatches(c, 'true', 'true'), isTrue);
      expect(fieldFilterMatches(c, false, 'true'), isFalse);
      expect(fieldFilterMatches(c, null, 'false'), isTrue);
    });

    test('tanggal: hari yang sama (nilai tersimpan berjam 00:00)', () {
      final d = _field(FieldType.date);
      expect(fieldFilterMatches(d, '2026-10-01T00:00:00.000', '2026-10-01'), isTrue);
      expect(fieldFilterMatches(d, '2026-10-01', '2026-10-01'), isTrue);
      expect(fieldFilterMatches(d, '2026-10-02T00:00:00.000', '2026-10-01'), isFalse);
      expect(fieldFilterMatches(d, null, '2026-10-01'), isFalse);
    });

    test('foto tidak difilter', () {
      expect(fieldFilterMatches(_field(FieldType.photo), const [], 'x'), isTrue);
    });
  });

  group('nilai default (SPEC §3.4)', () {
    FormFieldModel withDefault(FieldType type, String? value,
            {List<String>? options, double? min, double? max, String? unit}) =>
        FormFieldModel(
            id: 'f',
            label: 'F',
            type: type,
            options: options,
            min: min,
            max: max,
            unit: unit,
            defaultValue: value);
    final now = DateTime(2026, 10, 1, 7, 5, 42);

    test('nilai siap pakai per tipe', () {
      final cases = <(FormFieldModel, Object?)>[
        (withDefault(FieldType.text, 'Blok A'), 'Blok A'),
        (withDefault(FieldType.text, 'now'), 'now'),
        (withDefault(FieldType.textarea, 'baris 1\nbaris 2'), 'baris 1\nbaris 2'),
        (withDefault(FieldType.number, '35'), 35),
        (withDefault(FieldType.decimal, '2,5'), 2.5),
        (withDefault(FieldType.date, '2026-09-30'), '2026-09-30T00:00:00.000'),
        (withDefault(FieldType.date, 'now'), '2026-10-01T00:00:00.000'),
        (withDefault(FieldType.time, '06:30'), '06:30'),
        (withDefault(FieldType.time, 'now'), '07:05'),
        (withDefault(FieldType.datetime, '2026-09-30 06:30'),
            '2026-09-30T06:30:00.000'),
        (withDefault(FieldType.datetime, 'NOW'), '2026-10-01T07:05:00.000'),
        (withDefault(FieldType.dropdown, 'Tikus', options: _opts), 'Tikus'),
        (withDefault(FieldType.multiselect, 'Tikus; Ulat api', options: _opts),
            'Ulat api; Tikus'),
        (withDefault(FieldType.checkbox, 'true'), true),
        (withDefault(FieldType.checkbox, 'false'), false),
        (withDefault(FieldType.rating, '4'), 4),
      ];
      for (final (field, expected) in cases) {
        expect(resolveDefaultValue(field, now), expected,
            reason: '${field.type.name} "${field.defaultValue}"');
      }
    });

    test('tanpa default, kosong, atau tidak valid → tidak diterapkan', () {
      final cases = [
        withDefault(FieldType.text, null),
        withDefault(FieldType.text, ''),
        withDefault(FieldType.number, '250', max: 200),
        withDefault(FieldType.number, 'banyak'),
        withDefault(FieldType.time, '25:00'),
        withDefault(FieldType.date, 'besok'),
        withDefault(FieldType.dropdown, 'Babi', options: _opts),
        withDefault(FieldType.multiselect, 'Tikus; Babi', options: _opts),
        withDefault(FieldType.checkbox, 'ya'),
        withDefault(FieldType.rating, '7'),
        withDefault(FieldType.photo, 'x'),
      ];
      for (final field in cases) {
        expect(resolveDefaultValue(field, now), isNull,
            reason: '${field.type.name} "${field.defaultValue}"');
      }
    });

    test('pesan masalah default untuk builder', () {
      expect(defaultValueIssue(withDefault(FieldType.decimal, '250',
              min: 0, max: 200, unit: 'cm')),
          'must be between 0 and 200 cm');
      expect(defaultValueIssue(withDefault(FieldType.number, 'x')),
          'is not a valid number');
      expect(defaultValueIssue(withDefault(FieldType.dropdown, 'Babi',
              options: _opts)),
          'is not one of the options');
      expect(defaultValueIssue(withDefault(FieldType.multiselect, 'Babi',
              options: _opts)),
          'has an option that is not in the list: Babi');
      expect(defaultValueIssue(withDefault(FieldType.time, '7.15')),
          'is not a valid time');
      expect(defaultValueIssue(withDefault(FieldType.rating, '0')),
          'must be 1–5');
      expect(defaultValueIssue(withDefault(FieldType.time, 'now')), isNull);
      expect(defaultValueIssue(withDefault(FieldType.text, '')), isNull);
    });

    test('bentuk simpan default dari builder: format §3.1, `now` tetap', () {
      expect(normalizeDefaultValue(withDefault(FieldType.decimal, '2,50')), '2.5');
      expect(normalizeDefaultValue(withDefault(FieldType.number, '35.0')), '35');
      expect(normalizeDefaultValue(withDefault(FieldType.date, '2026-09-30')),
          '2026-09-30T00:00:00.000');
      expect(normalizeDefaultValue(withDefault(FieldType.datetime, 'Now')), 'now');
      expect(normalizeDefaultValue(withDefault(FieldType.time, '6:30')), isNull);
      expect(normalizeDefaultValue(withDefault(FieldType.time, '06:30')), '06:30');
      expect(normalizeDefaultValue(withDefault(FieldType.checkbox, 'TRUE')), 'true');
      expect(normalizeDefaultValue(withDefault(FieldType.text, ' apa adanya ')),
          ' apa adanya ');
      expect(normalizeDefaultValue(withDefault(FieldType.text, '   ')), isNull);
    });
  });
}
