import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:ui' as ui;
import '../tile_cache_sqlite_service.dart';
import '../tile_download_manager.dart';

/// Custom TileProvider with SQLite cache + offline parent-tile fallback.
///
/// Load order:
///   1. SQLite cache hit            → instant, no network
///   2. Network download (if online) → save to cache, return tile
///   3. Parent tile crop/scale      → walk up to 3 zoom levels, crop sub-region
///   4. Grey placeholder            → shows tile boundary, never blank white
class SqliteCachedTileProvider extends TileProvider {
  final TileCacheSqliteService _cacheService;
  final TileDownloadManager _downloadManager;
  final String basemapId;
  final Duration maxStale;

  SqliteCachedTileProvider({
    required this.basemapId,
    this.maxStale = const Duration(days: 30),
  })  : _cacheService = TileCacheSqliteService(),
        _downloadManager = TileDownloadManager();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _SqliteTileImage(
      url:             getTileUrl(coordinates, options),
      coordinates:     coordinates,
      basemapId:       basemapId,
      cacheService:    _cacheService,
      downloadManager: _downloadManager,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SqliteTileImage extends ImageProvider<_SqliteTileImage> {
  final String url;
  final TileCoordinates coordinates;
  final String basemapId;
  final TileCacheSqliteService cacheService;
  final TileDownloadManager downloadManager;

  const _SqliteTileImage({
    required this.url,
    required this.coordinates,
    required this.basemapId,
    required this.cacheService,
    required this.downloadManager,
  });

  // ── Connectivity cache (shared across all tile loads) ─────────────────────
  static bool _isOnline = true;
  static DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _checkTtl = Duration(seconds: 30);
  static Completer<bool>? _checkCompleter;

  /// DNS-based connectivity check with 30s TTL.
  /// Concurrent calls share the same in-flight request.
  static Future<bool> _checkConnectivity(String host) async {
    final now = DateTime.now();
    if (now.difference(_lastCheck) < _checkTtl) return _isOnline;

    // Deduplicate concurrent checks
    if (_checkCompleter != null) return _checkCompleter!.future;

    final completer = Completer<bool>();
    _checkCompleter = completer;

    bool result = false;
    try {
      final addrs = await InternetAddress.lookup(
        host.isNotEmpty ? host : 'tile.openstreetmap.org',
      ).timeout(const Duration(seconds: 3));
      result = addrs.isNotEmpty && addrs.first.rawAddress.isNotEmpty;
    } catch (_) {
      result = false;
    }

    _isOnline = result;
    _lastCheck = DateTime.now();
    _checkCompleter = null;
    completer.complete(result);
    return result;
  }

  // ── ImageProvider boilerplate ─────────────────────────────────────────────

  @override
  Future<_SqliteTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SqliteTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _SqliteTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec:      _loadAsync(key, decode),
      scale:      1.0,
      debugLabel: url,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<_SqliteTileImage>('Image key', key),
      ],
    );
  }

  // ── Main load pipeline ────────────────────────────────────────────────────

  Future<ui.Codec> _loadAsync(
      _SqliteTileImage key, ImageDecoderCallback decode) async {
    final z = coordinates.z.toInt();
    final x = coordinates.x.toInt();
    final y = coordinates.y.toInt();

    try {
      // ── 1. Cache hit ──────────────────────────────────────────────────────
      final cached = await cacheService.getTile(
        basemapId: basemapId, z: z, x: x, y: y,
      );
      if (cached != null) {
        final buf = await ui.ImmutableBuffer.fromUint8List(cached);
        return decode(buf);
      }

      // ── 2. PDF / sqlite-only basemap → skip network ───────────────────────
      final isPdf = url.isEmpty ||
          url.startsWith('sqlite://') ||
          url.startsWith('overlay://');
      if (isPdf) {
        return await _tryParentFallback(z, x, y, decode) ??
            await _createPlaceholder(decode);
      }

      // ── 3. Connectivity check (DNS, cached 30 s) ──────────────────────────
      final host = Uri.tryParse(url)?.host ?? '';
      final online = await _checkConnectivity(host);

      if (online) {
        // ── 4. Download from network ────────────────────────────────────────
        final bytes = await downloadManager.downloadTile(
          url: url, z: z, x: x, y: y, isVisible: true,
        );
        if (bytes != null) {
          // Save to cache — non-blocking, errors silently ignored
          cacheService
              .saveTile(basemapId: basemapId, z: z, x: x, y: y, tileData: bytes)
              .catchError((_) {});
          final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buf);
        }
      }

      // ── 5. Offline / download failed → parent tile fallback ───────────────
      return await _tryParentFallback(z, x, y, decode) ??
          await _createPlaceholder(decode);
    } catch (e) {
      debugPrint('❌ Tile error z=$z,x=$x,y=$y: $e');
      return await _tryParentFallback(z, x, y, decode) ??
          await _createPlaceholder(decode);
    }
  }

  // ── Parent tile fallback ──────────────────────────────────────────────────

  /// Ask the cache for a parent tile, then crop & scale it.
  /// Returns null if no parent is cached at all.
  Future<ui.Codec?> _tryParentFallback(
      int z, int x, int y, ImageDecoderCallback decode) async {
    try {
      final parent = await cacheService.getParentTile(
        basemapId: basemapId, z: z, x: x, y: y,
      );
      if (parent == null) return null;
      return await _cropParentTile(parent.data, parent.zoomDelta, x, y, decode);
    } catch (e) {
      debugPrint('⚠️ Parent fallback failed z=$z,x=$x,y=$y: $e');
      return null;
    }
  }

  /// Crop and scale the sub-region of a parent tile that corresponds to
  /// the requested tile coordinate.
  ///
  /// Math (tile size = 256 px):
  ///   subSize = 256 >> dz          → 128, 64, 32 for dz 1, 2, 3
  ///   subX    = (x % (1<<dz)) * subSize
  ///   subY    = (y % (1<<dz)) * subSize
  ///
  /// Draw Rect(subX, subY, subSize, subSize) → scaled to Rect(0, 0, 256, 256).
  Future<ui.Codec> _cropParentTile(
    Uint8List parentData,
    int dz,
    int x,
    int y,
    ImageDecoderCallback decode,
  ) async {
    // Decode parent PNG
    final parentBuf = await ui.ImmutableBuffer.fromUint8List(parentData);
    final parentCodec = await decode(parentBuf);
    final frame = await parentCodec.getNextFrame();
    final parentImg = frame.image;

    try {
      final subSize = 256 >> dz;
      final subX    = (x % (1 << dz)) * subSize;
      final subY    = (y % (1 << dz)) * subSize;

      // Render onto 256×256 canvas
      final recorder = ui.PictureRecorder();
      final canvas   = ui.Canvas(
        recorder,
        const ui.Rect.fromLTWH(0, 0, 256, 256),
      );
      canvas.drawImageRect(
        parentImg,
        ui.Rect.fromLTWH(
          subX.toDouble(), subY.toDouble(),
          subSize.toDouble(), subSize.toDouble(),
        ),
        const ui.Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture    = recorder.endRecording();
      final scaledImg  = await picture.toImage(256, 256);

      try {
        final byteData = await scaledImg.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) return await _createPlaceholder(decode);

        final outBuf = await ui.ImmutableBuffer.fromUint8List(
          byteData.buffer.asUint8List(),
        );
        return decode(outBuf);
      } finally {
        scaledImg.dispose();
      }
    } finally {
      parentImg.dispose();
    }
  }

  // ── Placeholder tile ──────────────────────────────────────────────────────

  /// Grey 256×256 tile with a 1-px border — clearly marks a missing tile
  /// without leaving the map blank white.
  Future<ui.Codec> _createPlaceholder(ImageDecoderCallback decode) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas   = ui.Canvas(
        recorder,
        const ui.Rect.fromLTWH(0, 0, 256, 256),
      );

      // Light grey fill
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..color = const ui.Color(0xFFE8E8E8),
      );
      // Subtle tile-boundary border
      canvas.drawRect(
        const ui.Rect.fromLTWH(1, 1, 254, 254),
        ui.Paint()
          ..color       = const ui.Color(0xFFCCCCCC)
          ..strokeWidth = 1
          ..style       = ui.PaintingStyle.stroke,
      );

      final picture  = recorder.endRecording();
      final image    = await picture.toImage(256, 256);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData != null) {
        final buf = await ui.ImmutableBuffer.fromUint8List(
          byteData.buffer.asUint8List(),
        );
        return decode(buf);
      }
    } catch (_) {
      // Fall through to hardcoded bytes
    }

    // Last resort: minimal valid transparent PNG (1×1 pixel)
    final fallback = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    final buf = await ui.ImmutableBuffer.fromUint8List(fallback);
    return decode(buf);
  }

  // ── Identity ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _SqliteTileImage &&
          other.url == url &&
          other.basemapId == basemapId &&
          other.coordinates == coordinates);

  @override
  int get hashCode => Object.hash(url, basemapId, coordinates);
}
