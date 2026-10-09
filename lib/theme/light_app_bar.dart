import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// AppBar terang untuk halaman project (template): latar warna halaman, ikon
/// dan judul gelap.
///
/// Tema app memasang `iconTheme` dan `titleTextStyle` putih secara eksplisit
/// untuk AppBar hijau. Keduanya mengalahkan `foregroundColor`, jadi warna
/// ikon kembali/aksi/menu dan judul harus ditimpa di sini — tanpa itu
/// tombolnya putih di atas latar terang (tidak terlihat).
AppBar lightAppBar({
  Widget? leading,
  Widget? title,
  List<Widget>? actions,
  double? titleSpacing,
}) {
  const iconTheme = IconThemeData(color: AppTheme.textPrimary);
  return AppBar(
    backgroundColor: AppTheme.scaffoldBackground,
    foregroundColor: AppTheme.textPrimary,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    elevation: 0,
    scrolledUnderElevation: 0,
    iconTheme: iconTheme,
    actionsIconTheme: iconTheme,
    titleTextStyle: const TextStyle(
      color: AppTheme.textPrimary,
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
    leading: leading,
    title: title,
    actions: actions,
    titleSpacing: titleSpacing,
  );
}
