import 'package:archive/archive.dart';

import 'layer_importer.dart';

/// Bongkar zip di memori → berkas (bukan folder). Zip rusak / bukan zip →
/// [LayerImportException] berlabel [label].
List<ArchiveFile> decodeZipOrThrow(List<int> bytes, String label) {
  try {
    return ZipDecoder().decodeBytes(bytes).files.where((f) => f.isFile).toList();
  } catch (e) {
    throw LayerImportException('$label is not a valid zip file');
  }
}
