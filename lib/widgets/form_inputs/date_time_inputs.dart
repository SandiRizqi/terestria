import 'package:flutter/material.dart';

import '../../utils/field_values.dart';

/// Input jam (24 jam). Nilai tersimpan `HH:mm`; kosong = `''`. Nilai lama
/// yang tidak valid tampil apa adanya (validasi form yang menandainya).
/// [onChanged] null = baca-saja (mis. nilai di-pin).
class TimeInput extends StatelessWidget {
  final Object? value;
  final ValueChanged<String>? onChanged;

  const TimeInput({super.key, required this.value, this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final current = parseTimeValue(value);
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? now
          : TimeOfDay(hour: current.hour, minute: current.minute),
      builder: _use24Hour,
    );
    if (picked != null) onChanged?.call(formatTimeValue(picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final time = parseTimeValue(value);
    return _PickerRow(
      icon: Icons.schedule,
      text: time != null
          ? formatTimeValue(time.hour, time.minute)
          : _rawText(value),
      onPick: onChanged == null ? null : () => _pick(context),
      onNow: onChanged == null
          ? null
          : () {
              final now = DateTime.now();
              onChanged!(formatTimeValue(now.hour, now.minute));
            },
      onClear: onChanged == null ? null : () => onChanged!(''),
    );
  }
}

/// Input tanggal + jam. Nilai tersimpan `YYYY-MM-DDTHH:mm:00.000` (lokal);
/// kosong = `''`. Pilih tanggal lalu jam; batal di salah satunya = tidak
/// berubah.
class DateTimeInput extends StatelessWidget {
  final Object? value;
  final ValueChanged<String>? onChanged;

  const DateTimeInput({super.key, required this.value, this.onChanged});

  static final _first = DateTime(2000);
  static final _last = DateTime(2100, 12, 31);

  Future<void> _pick(BuildContext context) async {
    final current = parseDateTimeValue(value);
    final base = current != null &&
            !current.isBefore(_first) &&
            current.isBefore(_last)
        ? current
        : DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _first,
      lastDate: _last,
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: _use24Hour,
    );
    if (time == null) return;
    onChanged?.call(formatDateTimeValue(
        DateTime(date.year, date.month, date.day, time.hour, time.minute)));
  }

  @override
  Widget build(BuildContext context) {
    final dt = parseDateTimeValue(value);
    return _PickerRow(
      icon: Icons.event,
      text: dt != null
          ? '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
              '${_two(dt.hour)}:${_two(dt.minute)}'
          : _rawText(value),
      onPick: onChanged == null ? null : () => _pick(context),
      onNow: onChanged == null
          ? null
          : () => onChanged!(formatDateTimeValue(DateTime.now())),
      onClear: onChanged == null ? null : () => onChanged!(''),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Teks nilai yang tidak bisa dibaca; null bila kosong.
String? _rawText(Object? value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

Widget _use24Hour(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    );

/// Baris nilai: ketuk untuk memilih, tombol "Now", dan hapus bila terisi.
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String? text;
  final VoidCallback? onPick;
  final VoidCallback? onNow;
  final VoidCallback? onClear;

  const _PickerRow({
    required this.icon,
    required this.text,
    required this.onPick,
    required this.onNow,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Colors.grey.shade600;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text ?? 'Not set',
                      overflow: TextOverflow.ellipsis,
                      style: text == null ? TextStyle(color: muted) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onNow != null)
          TextButton(onPressed: onNow, child: const Text('Now')),
        if (onClear != null && text != null)
          IconButton(
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.clear, size: 20),
          ),
      ],
    );
  }
}
