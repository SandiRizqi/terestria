import 'package:flutter/material.dart';

/// Skala 1–5: lima bintang yang bisa diketuk; ketuk bintang yang sedang
/// terpilih lagi untuk mengosongkan. [onChanged] null = baca-saja (mis. nilai
/// di-pin).
class RatingInput extends StatelessWidget {
  final int? value;
  final ValueChanged<int?>? onChanged;

  const RatingInput({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = value ?? 0;
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: 'Rate $i of 5',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: onChanged == null
                ? null
                : () => onChanged!(value == i ? null : i),
            icon: Icon(
              i <= current ? Icons.star_rounded : Icons.star_border_rounded,
              color: i <= current ? Colors.amber.shade700 : Colors.grey.shade500,
              size: 30,
            ),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value == null ? 'Not rated' : '$value / 5',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}
