import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Tombol tool peta yang SERAGAM untuk semua halaman ber-peta: ukuran, bentuk,
/// elevasi, dan ukuran ikon konsisten. Tema tetap seperti yang sudah ada —
/// kotak membulat putih dengan ikon hijau; saat [active] latar jadi berwarna.
///
/// Dipakai di dalam [MapControlsColumn] yang sudah menangani penempatan
/// (anchor kanan-bawah, spacing seragam) & responsif (mengecil proporsional di
/// layar pendek), sehingga tombol tak lagi campur FAB.small/mini/Container.
class MapToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Sedang aktif → latar [activeColor] (default hijau primary), ikon putih.
  final bool active;
  final Color? activeColor;

  /// Warna ikon saat tidak aktif (default hijau primary).
  final Color? iconColor;

  /// Badge opsional di pojok kanan-atas (mis. jumlah layer aktif).
  final Widget? badge;

  final double size;
  final double iconSize;

  const MapToolButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.activeColor,
    this.iconColor,
    this.badge,
    this.size = 44,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final bg = active ? (activeColor ?? AppTheme.primaryColor) : Colors.white;
    final fg = active ? Colors.white : (iconColor ?? AppTheme.primaryColor);

    Widget btn = Material(
      color: bg,
      elevation: 4,
      borderRadius: radius,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    if (badge != null) {
      btn = Stack(
        clipBehavior: Clip.none,
        children: [btn, Positioned(top: -2, right: -2, child: badge!)],
      );
    }
    return btn;
  }
}
