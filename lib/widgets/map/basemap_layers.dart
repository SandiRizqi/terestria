import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../config/api_config.dart';
import '../../models/basemap_model.dart';
import '../../services/basemap/pdf_overlay.dart';
import '../../services/tile_providers/sqlite_cached_tile_provider.dart';

/// Layer basemap untuk `FlutterMap` — dipakai DataCollection, Navigasi, dan
/// Notification Map.
///
/// Dipanggil di SETIAP build peta (bisa puluhan kali per detik), jadi TANPA
/// I/O berkas: overlay PDF sudah disiapkan lebih dulu oleh
/// `PdfOverlayController` ([overlay]). [fallback] = layer OSM milik layar.
///
/// Key per basemap memaksa layer dibangun ulang saat basemap diganti:
/// - TileLayer: flutter_map 7 hanya memuat ulang tile bila `urlTemplate`
///   berubah — semua PDF mode tile memakai `''`, sehingga tanpa key tile PDF
///   lama tetap tampil;
/// - overlay: dengan `gaplessPlayback: false`, gambar PDF lama tak ikut
///   digambar di batas PDF baru selama decode.
List<Widget> buildBasemapLayers(
  Basemap basemap, {
  required PdfOverlaySpec? overlay,
  required Widget Function() fallback,
}) {
  if (isPdfOverlayBasemap(basemap)) {
    final spec = overlay;
    return [
      fallback(),
      if (spec != null && spec.basemapId == basemap.id)
        OverlayImageLayer(
          key: ValueKey('pdf-overlay-${basemap.id}'),
          overlayImages: [
            OverlayImage(
              bounds: spec.bounds,
              imageProvider: spec.image,
              opacity: 1.0,
              gaplessPlayback: false,
            ),
          ],
        ),
    ];
  }

  // Basemap tile (online/custom/PDF mode tile) — SqliteCachedTileProvider agar
  // tile ter-cache tetap muncul saat offline. URL sqlite:// / overlay://
  // dikosongkan: tile diambil provider dari database lokal.
  return [
    TileLayer(
      key: ValueKey('basemap-${basemap.id}'),
      urlTemplate: basemap.urlTemplate.startsWith('sqlite://') ||
              basemap.urlTemplate.startsWith('overlay://')
          ? ''
          : basemap.urlTemplate,
      userAgentPackageName: ApiConfig.bundleName,
      minZoom: basemap.minZoom.toDouble(),
      maxZoom: basemap.maxZoom.toDouble(),
      tileProvider: SqliteCachedTileProvider(
        basemapId: basemap.id,
        maxStale: const Duration(days: 30),
      ),
    ),
  ];
}

/// Chip "Memuat peta PDF…" selama overlay di-decode. Letakkan sebagai anak
/// terakhir `FlutterMap`; tak menghalangi gestur peta.
class PdfOverlayLoadingChip extends StatelessWidget {
  const PdfOverlayLoadingChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: IgnorePointer(
        child: Material(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 8),
                Text(
                  'Memuat peta PDF…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
