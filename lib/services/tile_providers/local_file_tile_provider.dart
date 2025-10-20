import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class LocalFileTileProvider extends TileProvider {
  final String basePath;

  LocalFileTileProvider(this.basePath);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final z = coordinates.z.round();
    final x = coordinates.x.round();
    final y = coordinates.y.round();
    final filePath = '$basePath/$z/$x/$y.png';
    return LocalFileImageProvider(File(filePath));
  }
}

class LocalFileImageProvider extends ImageProvider<LocalFileImageProvider> {
  final File file;

  const LocalFileImageProvider(this.file);

  @override
  Future<LocalFileImageProvider> obtainKey(ImageConfiguration configuration) {
    // gunakan bawaan Flutter
    return SynchronousFuture<LocalFileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadBuffer(
    LocalFileImageProvider key,
    DecoderBufferCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: file.path,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<LocalFileImageProvider>('Image key', key);
      },
    );
  }

  Future<ui.Codec> _loadAsync(
    LocalFileImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    try {
      assert(key == this);

      if (!await file.exists()) {
        final transparentPng = _createTransparentPng();
        final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
        return decode(buffer);
      }

      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      final transparentPng = _createTransparentPng();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
      return decode(buffer);
    }
  }

  Uint8List _createTransparentPng() {
    return Uint8List.fromList([
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
  }

  @override
  bool operator ==(Object other) =>
      other is LocalFileImageProvider && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;

  @override
  String toString() =>
      '${objectRuntimeType(this, 'LocalFileImageProvider')}("${file.path}")';
}
