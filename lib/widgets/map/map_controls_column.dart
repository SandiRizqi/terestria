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

    // PENTING: JANGAN bungkus dengan SingleChildScrollView. Scrollable menyerap
    // sentuhan di SELURUH persegi viewport-nya (termasuk celah antar-tombol dan
    // ruang kosong di kiri tombol yang right-aligned), sehingga tap ke PETA di
    // belakang kolom ini tak sampai — terasa "terhalang komponen lain",
    // terutama saat toolbar measure melebarkan kolom.
    //
    // Column biasa TIDAK hit-test ruang kosong (hanya tombol asli yang
    // memblokir), jadi tap di sela-sela tembus ke peta. Batasi tinggi dengan
    // ConstrainedBox + FittedBox(scaleDown) supaya di layar sangat pendek kolom
    // mengecil proporsional alih-alih overflow — tanpa perlu scroll.
    return Positioned(
      right: right,
      bottom: bottom,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomRight,
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
