import 'package:xml/xml.dart';

import 'layer_importer.dart';

/// Helper XML bersama konverter GPX & KML — mencocokkan nama elemen lokal
/// (abaikan namespace/prefix) agar berkas dari berbagai aplikasi terbaca.

XmlDocument parseXmlOrThrow(String text, String label) {
  try {
    return XmlDocument.parse(text);
  } catch (e) {
    throw LayerImportException('$label tidak valid: $e');
  }
}

/// Anak langsung [parent] dengan nama lokal [local].
Iterable<XmlElement> childrenNamed(XmlElement parent, String local) =>
    parent.childElements.where((e) => e.name.local == local);

/// Semua turunan [parent] dengan nama lokal [local].
Iterable<XmlElement> descendantsNamed(XmlElement parent, String local) =>
    parent.descendantElements.where((e) => e.name.local == local);

/// Teks anak langsung pertama bernama [local], dirapikan; null bila kosong.
String? childText(XmlElement parent, String local) {
  final e = childrenNamed(parent, local).firstOrNull;
  final t = e?.innerText.trim();
  return (t == null || t.isEmpty) ? null : t;
}
