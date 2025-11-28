import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Overlay Image Provider for GeoPDF basemaps
/// This displays the entire PDF as a single georeferenced image
class GeoPdfOverlayImageProvider extends ImageProvider<GeoPdfOverlayImageProvider> {
  final String imagePath;
  final LatLngBounds bounds;

  const GeoPdfOverlayImageProvider({
    required this.imagePath,
    required this.bounds,
  });

  @override
  Future<GeoPdfOverlayImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<GeoPdfOverlayImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    GeoPdfOverlayImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: imagePath,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<GeoPdfOverlayImageProvider>('Image key', key);
      },
    );
  }

  Future<ui.Codec> _loadAsync(
    GeoPdfOverlayImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      assert(key == this);

      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Overlay image not found: $imagePath');
      }

      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      print('Error loading overlay image: $e');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPdfOverlayImageProvider &&
      other.imagePath == imagePath;

  @override
  int get hashCode => imagePath.hashCode;

  @override
  String toString() => 
      '${objectRuntimeType(this, 'GeoPdfOverlayImageProvider')}("$imagePath")';
}
