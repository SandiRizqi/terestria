import 'package:flutter/material.dart';

/// Tumpukan tombol kontrol di sisi kanan peta sebagai SATU kolom ber-spacing,
/// di-anchor dari bawah. Menggantikan banyak `Positioned` dengan `bottom:`
/// hitung-hitungan yang bisa saling menumpuk di layar/ukuran berbeda.
///
/// [children] diberi urutan atas→bawah (item terakhir menempel paling bawah).
/// Bila total tinggi melebihi ruang, kolom bisa di-scroll (dari bawah) sehingga
/// tetap tak menumpuk pada device pendek.
class MapControlsColumn extends StatelessWidget {
  final List<Widget> children;
  final double bottom;
  final double right;
  final double spacing;

  /// Batas atas kolom (agar tak menabrak app bar) — sisakan ruang dari atas.
  final double topInset;

  const MapControlsColumn({
    super.key,
    required this.children,
    this.bottom = 16,
    this.right = 16,
    this.spacing = 12,
    this.topInset = 96,
  });

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(height: spacing));
      spaced.add(children[i]);
    }

    final maxHeight =
        MediaQuery.of(context).size.height - bottom - topInset;

    return Positioned(
      right: right,
      bottom: bottom,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
        child: SingleChildScrollView(
          reverse: true, // anchor & scroll dari bawah
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: spaced,
          ),
        ),
      ),
    );
  }
}
