# SPEC — Style per Feature + Select Feature dengan Tap Langsung

> Status: **disetujui user (2026-09-30)**; revisi setelah review disetujui 2026-10-01 (lihat `tasks/plan.md`) · Tanggal: 2026-09-30
> Repo: **terestria** (Flutter, package `geoform_app`) + **gis-backend** (Django, app `mobile`).
> Spec sebelumnya (Multi-Project Concurrent Tracking) diarsip di `tasks/spec-multi-project-tracking.md`.

## 1. Objective

**Siapa:** surveyor lapangan yang mengumpulkan data point/line/polygon per project.

**Masalah sekarang:**
1. Semua feature project digambar dengan **satu style default** dari Settings aplikasi. Contohnya polygon yang digambar di peta project (`_buildMarkerCache`, `data_collection_screen.dart:966`) dan di layar navigasi (`navigation_screen.dart:1384`). Sesama feature tidak bisa dibedakan secara visual, misalnya blok yang sudah dicek dan yang belum.
2. Line dan polygon hanya bisa dipilih lewat **ikon info di tengah feature** (titik tengah line atau centroid polygon). Pada line panjang atau polygon besar, ikon itu sering di luar layar atau menumpuk.

**Yang dibangun:**
1. **Style per feature.** Saat mengisi form data (dan saat mengedit data tersimpan), user bisa mengganti style feature itu: warna, ukuran/tebal, opacity, dan warna garis tepi, seperti editor style di Layers. Kalau tidak diubah, feature tetap memakai default. Style **ikut sync ke server**.
2. **Select dengan tap langsung.** Tap pada point, line, atau area polygon langsung membuka detailnya, jadi ikon info di tengah dihapus. Kalau satu tap mengenai beberapa feature, muncul **daftar pilihan**.

### Keputusan terkonfirmasi user
| Aspek | Keputusan |
|---|---|
| Penyimpanan style | **Ikut sync ke server** (kolom baru di backend, butuh migrasi). Web dashboard menampilkannya lewat pilihan **Warna peta**: status verifikasi atau style feature (revisi 2026-10-01). |
| Verifikasi di dashboard (revisi 2026-10-01) | Perubahan style atau foto saja **tidak** me-reset verifikasi. Reset hanya bila isian form non-foto atau koordinat titik berubah. |
| Tap mengenai beberapa feature | **Tampilkan daftar pilihan** |
| Ikon info di tengah line/polygon | **Dihapus**, di peta project dan layar navigasi |
| Properti style | **Sama seperti Layers** (lihat §3) |

### Asumsi (dinyatakan ke user; koreksi sebelum disetujui)
1. **Default tetap dari Settings.** Feature tanpa style mengikuti Settings, termasuk kalau Settings diubah belakangan. Begitu style diubah, feature menyimpan salinan lengkap style itu.
2. **Letak pengaturan style.** Bagian **"Style"** di bawah field form "Survey data", bisa dibuka-tutup, dengan pratinjau dan tombol **"Use default"**. Bagian yang sama ada di layar edit data tersimpan.
3. **"Save & next"** membawa style terakhir ke data berikutnya dalam sesi yang sama. Membuka project lagi dimulai dengan default.
4. **Cakupan tampilan style:** peta project, layar navigasi, dan peta data survei di web dashboard (lewat pilihan warna, revisi 2026-10-01). File ekspor (GeoJSON/KML/SHP) dan laporan PDF belum.
5. **Tap langsung hanya di peta project.** Layar navigasi hanya menampilkan style dan tidak lagi memakai ikon info.
6. **Prioritas tap tidak berubah.** Alat ukur aktif → tap menambah titik ukur. Mode gambar (bukan tracking) → tap menambah titik. Di luar itu → tap memilih feature, termasuk saat tracking berjalan.
7. **Cluster point** pada zoom rendah tetap seperti sekarang; tap langsung berlaku untuk point yang tidak ter-cluster.

## 2. Tech Stack
- **Mobile:**
  - Flutter SDK `^3.5.1`
  - `flutter_map ^7.0.2`, `latlong2 ^0.9.1`
  - `sqflite ^2.3.0` (DB lokal, sekarang versi 6)
  - `flutter_colorpicker ^1.0.3` (sudah dipakai editor Layers)
  - Tanpa dependency baru.
- **Backend:** Django 4.2 + DRF, PostgreSQL (`JSONField`), Python 3.9 (conda `django-env`).
- **Web dashboard** (revisi 2026-10-01): `gis-dashboard`, Next.js 13 + MapLibre; test helper murni dengan `node --test`.

## 3. Model Style & Kontrak Data

Properti mengikuti `LayerStyle` (`lib/models/layer_model.dart`) supaya editor Layers bisa dipakai ulang:

| Geometri | Yang bisa diatur | Dipakai saat render |
|---|---|---|
| Point | warna, ukuran, opacity | `fillColor` + `fillOpacity`, `pointSize` |
| Line | warna, tebal, opacity | `strokeColor` + `fillOpacity`, `strokeWidth` (sama seperti layer line sekarang) |
| Polygon | warna isi, opacity isi, warna garis tepi, tebal garis tepi | `fillColor` + `fillOpacity`, `strokeColor`, `strokeWidth` |

- **Rentang nilai:** `fillOpacity` 0.05–1.0 dan `strokeWidth` 0.5–10 (sama dengan slider Layers); `pointSize` 10–24, yang memetakan diameter marker 20–48 dp. Revisi 2026-10-01: sebelumnya `pointSize` 4–20, padahal 4–10 tampil sama besar dan Settings mengizinkan sampai 24.
- **Nilai awal editor** diambil dari Settings sesuai render default sekarang:

  | Geometri | Nilai awal |
  |---|---|
  | Point | `pointColor`, opacity 1.0, `pointSize` |
  | Line | `lineColor`, opacity 0.8, `lineWidth` |
  | Polygon | isi `polygonColor` dengan `polygonOpacity`; garis tepi `polygonColor`, tebal `lineWidth` |

**Format JSON** (DB lokal, payload sync, dan backend). Warna ditulis `#RRGGBB`, opacity terpisah, supaya bisa dipakai web kelak:
```json
"style": {
  "fillColor": "#FF9800",
  "fillOpacity": 0.3,
  "strokeColor": "#E65100",
  "strokeWidth": 2.0,
  "pointSize": 12
}
```

**Aturan sync** (dicatat juga di `docs/sync-push-contract.md`):

| Kejadian | Aturan |
|---|---|
| Push dari app baru | **Selalu** mengirim key `style`: objek bila di-custom, `null` bila memakai default (termasuk setelah "Use default"). |
| Backend menerima payload **tanpa** key `style` (app versi lama, atau edit dari dashboard) | Style yang tersimpan **dipertahankan**. |
| Backend menerima `null` | Style dihapus. |
| Backend menerima style tidak valid (key inti hilang, tipe salah, di luar rentang) | Style **dibuang** (tidak disimpan), record **tetap diterima**. Style tidak boleh menggagalkan sync data. |
| Backend menerima style dengan key asing | Key asing **diabaikan**, 5 key inti disimpan (revisi 2026-10-01), supaya app versi baru bisa menambah properti. |
| Update yang hanya mengubah style atau foto, atau tidak mengubah isi | Verifikasi record di dashboard **dipertahankan** (revisi 2026-10-01). |
| Pull | `to_mobile_json` menyertakan `style`. |
| Pull dari backend lama (key `style` tidak ada) | Style lokal dipertahankan. |
| Pull dengan `style: null` | Style lokal dihapus. |
| Konflik versi (409) dan "Use server version" | Ikut membawa style versi server. |

**DB lokal v7:** kolom `geo_data.style TEXT` (JSON, boleh null). Migrasinya idempoten memakai pola `missingColumns`, dan record lama berisi `style = null`. Draft koleksi ikut menyimpan style. Cadangan ZIP otomatis ikut karena memakai `GeoData.toJson`.

**Backend:** field `GeoData.style = JSONField(null=True, blank=True)` + migrasi `0021`, validasi di serializer, dan `to_mobile_json` menyertakan `style`. Tile peta web (MVT) membawa 5 properti style datar: `style_fill_color`, `style_fill_opacity`, `style_stroke_color`, `style_stroke_width`, `style_point_size` (migrasi `0022`, revisi 2026-10-01).

## 4. Commands

**Mobile** (`D:\Developments\terestria`):
```
flutter pub get
flutter analyze        # baseline: 0 error, 29 warning — tidak boleh bertambah
flutter test           # baseline: 641 test lulus
flutter test test/models/feature_style_test.dart
```

**Backend** (`D:\Developments\gis-backend`, Git Bash):
```
PY="/c/Users/User/.conda/envs/django-env/python.exe"
export PATH="/c/Users/User/.conda/envs/django-env/Library/bin:$PATH"
"$PY" manage.py makemigrations mobile        # sekali, untuk kolom style
"$PY" -m unittest mobile.tests_feature_style mobile.tests_push_rules mobile.tests_pull_filter
"$PY" manage.py check
```
Test yang butuh DB (`mobile/tests_feature_style_db.py`) hanya jalan di CI, karena pembuatan DB test di lokal dilarang.

## 5. Project Structure (file baru / disentuh)

**Mobile**

| File | Isi |
|---|---|
| `lib/models/feature_style.dart` | **baru**: style feature ↔ JSON (hex), nilai awal dari Settings, clamp rentang. Memakai ulang `LayerStyle`. |
| `lib/models/geo_data_model.dart` | field `style` (nullable), `toJson`/`fromJson`/`copyWith` |
| `lib/services/database_service.dart` | DB v7: kolom `style`, baca/tulis |
| `lib/services/sync_service.dart` | kirim `style` saat push; baca `style` saat pull, sesuai aturan §3 |
| `lib/services/collection_draft_service.dart` | draft ikut menyimpan style |
| `lib/widgets/style/style_editor.dart` | **baru**: editor style bersama (warna, slider, pratinjau), dipindah dari `layers_screen.dart` |
| `lib/screens/layers/layers_screen.dart` | memakai editor bersama, tanpa perubahan perilaku |
| `lib/widgets/style/feature_style_section.dart` | **baru**: bagian "Style" di form (ringkasan saat tertutup, "Use default") |
| `lib/services/map/feature_hit_test.dart` | **baru**: fungsi murni "feature mana yang kena tap" |
| `lib/widgets/map/feature_pick_sheet.dart` | **baru**: daftar pilihan saat tap mengenai lebih dari satu feature |
| `lib/screens/data_collection/data_collection_screen.dart` | render style per feature, tap langsung, hapus ikon info, bagian Style di form "Survey data". File ini sudah ±4.350 baris, jadi logika baru ditaruh di file terpisah. |
| `lib/screens/project/edit_geo_data_screen.dart` | ubah/reset style data tersimpan |
| `lib/screens/navigation/navigation_screen.dart` | render style per feature, hapus ikon info |
| `docs/sync-push-contract.md` | tambah `style` |

Semua file `*.md` di-gitignore, jadi dokumen ini di-commit dengan `git add -f`.

**Test mobile** (`test/…`, mengikuti pola yang ada):
- `test/models/feature_style_test.dart`
- `test/services/db_v7_test.dart`
- `test/services/sync_feature_style_test.dart`
- `test/services/feature_hit_test_test.dart`
- `test/widgets/feature_style_section_test.dart`
- `test/widgets/feature_pick_sheet_test.dart`

**Backend**

| File | Isi |
|---|---|
| `mobile/models.py` | `GeoData.style` + `to_mobile_json` |
| `mobile/migrations/0021_geodata_style.py` | migrasi kolom |
| `mobile/serializers.py` | terima dan validasi `style`; key tidak ada berarti dipertahankan |
| `mobile/validation.py` | `clean_style()` |
| `mobile/tests_feature_style.py` | test dengan mock, jalan di lokal |
| `mobile/tests_feature_style_db.py` | test dengan DB, jalan di CI |

## 6. Code Style

Ikuti pola yang ada:
- Model immutable dengan `copyWith`/`toJson`/`fromJson`.
- Komentar dan nama test dalam bahasa Indonesia.
- Teks UI dalam bahasa Inggris.
- Logika murni dipisah dari widget agar bisa diuji.

Contoh model yang ada di repo (`lib/models/layer_model.dart`):
```dart
class LayerStyle {
  final Color fillColor;
  final double fillOpacity;
  final Color strokeColor;
  final double strokeWidth;
  final double pointSize;

  LayerStyle copyWith({Color? fillColor, double? fillOpacity, /* … */}) =>
      LayerStyle(
        fillColor: fillColor ?? this.fillColor,
        fillOpacity: fillOpacity ?? this.fillOpacity,
        // …
      );
}
```

Contoh gaya test yang ada (`test/widgets/conflict_sheet_test.dart`):
```dart
testWidgets('sheet: Keep mine / Use server memanggil resolve; berhasil → kartu '
    'hilang, gagal → pesan tampil', (tester) async {
  tester.view.physicalSize = const Size(360, 740); // HP 360 dp
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // …
});
```

Backend mengikuti pola `mobile/tests_push_rules.py`: ORM di-mock, dan komentar/docstring dalam bahasa Indonesia.

## 7. Testing Strategy

TDD: test merah dulu, satu commit per task.

- **Unit (Dart):**
  - style ↔ JSON (hex, clamp, key asing diabaikan);
  - nilai awal dari Settings per geometri;
  - `GeoData` dengan style (format lokal dan server, key tidak ada vs `null`);
  - migrasi DB v6 → v7 tanpa kehilangan data (pola `db_v6_test.dart`);
  - payload push selalu berisi `style`;
  - pull mengikuti aturan §3.
- **Unit hit-test:**
  - point dalam radius marker;
  - line dalam toleransi dari segmen;
  - polygon di dalam area atau dekat garis tepi;
  - banyak hit → semua dikembalikan dengan urutan stabil;
  - tidak ada hit → kosong;
  - toleransi dalam piksel layar, sehingga ikut zoom;
  - dua tingkat (revisi 2026-10-01): yang kena langsung (di dalam marker atau polygon, di atas garis) didahulukan; toleransi hanya dipakai bila tidak ada yang kena langsung.
- **Widget** (lebar 360 dp, tanpa overflow):
  - bagian Style di form: ringkasan "Default", ubah warna/ukuran memperbarui pratinjau, "Use default" me-reset;
  - daftar pilihan: menampilkan semua hit (judul, swatch warna) dan mengembalikan pilihan;
  - editor Layers tetap berfungsi (regresi).
- **Backend:**
  - mock: style valid tersimpan; tidak valid dibuang tanpa menolak record; key tidak ada berarti dipertahankan; `null` berarti dihapus; `to_mobile_json` menyertakan `style`;
  - CI: round-trip dengan DB nyata dan migrasi.
- **Manual di HP:**
  - ketepatan tap pada line tipis dan polygon kecil;
  - polygon bertumpuk memunculkan daftar pilihan;
  - performa dengan banyak feature;
  - upgrade dari versi app sebelumnya;
  - style tampil di HP kedua setelah pull.

## 8. Boundaries

- **Always**
  - TDD per task.
  - Sebelum commit, `flutter test` hijau dan `flutter analyze` tidak menambah warning.
  - Sync tetap kompatibel dua arah: app lama ↔ backend baru, app baru ↔ backend lama.
  - Style selalu opsional.
  - Tap untuk menambah titik (mode gambar) dan alat ukur tidak berubah.
- **Ask first**
  - Menambah dependency.
  - Mengubah makna default di Settings.
  - Menyentuh web dashboard.
  - Mengubah kontrak sync selain `style`.
- **Never**
  - Menyentuh `lib/config/api_config.dart`, perubahan lokal `pubspec.yaml`, atau git stash "temporary api_config changes".
  - Men-stage `gisbackend/__pycache__/*.pyc`.
  - Push atau deploy tanpa diminta.
  - Menggagalkan sync data karena style.
  - Menghapus field/record lama saat migrasi.

## 9. Success Criteria
1. Form "Survey data" punya bagian **Style** di bawah field. Saat tertutup, bagian ini menampilkan "Default" atau ringkasan warna. Isinya sesuai geometri project (§3), pratinjaunya berubah langsung, dan "Use default" mengembalikan ke default.
2. Feature yang disimpan dengan style custom tampil dengan style itu di peta project dan layar navigasi. Feature tanpa style tampil dengan default Settings terkini.
3. Style bisa diubah dan di-reset dari layar edit data tersimpan. Setelah disimpan, record jadi "belum sync" dan style ikut terkirim.
4. "Save & next" membawa style terakhir ke data berikutnya. Draft koleksi menyimpan style.
5. Style bertahan setelah app ditutup. Upgrade DB v6 → v7 tidak menghilangkan data, dan record lama bernilai `style = null`.
6. Sync memenuhi semua aturan di §3.
7. Di peta project, tap pada point/line/polygon membuka detail record, dan ikon info di tengah line/polygon tidak ada lagi. Layar navigasi juga tanpa ikon info.
8. Tap yang mengenai lebih dari satu feature memunculkan daftar pilihan, dan memilih satu membuka detailnya. Tap yang tidak mengenai feature tidak melakukan apa-apa.
9. Alat ukur dan mode gambar tetap memakai tap untuk menambah titik, tanpa membuka detail.
10. Web dashboard dan aplikasi mobile versi lama tetap berjalan normal. Kolom tambahan diabaikan, dan style tidak hilang saat data diedit dari dashboard.
11. `flutter analyze` tanpa warning baru dan `flutter test` hijau. Unittest backend dan `manage.py check` bersih, dan test DB lulus di CI.
12. Perubahan style atau foto saja tidak mengubah status verifikasi record di dashboard (revisi 2026-10-01).
13. Tap di dalam satu blok yang bersebelahan dengan blok lain langsung membuka detail blok itu, tanpa daftar pilihan (revisi 2026-10-01).
14. Peta data survei di web dashboard punya pilihan **Warna peta** (status verifikasi / style feature) dengan legenda yang menyebut mode aktif (revisi 2026-10-01).

## 10. Open Questions (tidak menghalangi, default dipakai bila tidak dijawab)
1. **Ekspor GeoJSON/KML/SHP dan laporan PDF** — belum ikut style. Default: tahap berikutnya.
2. **Web dashboard** — terjawab sebagian (2026-10-01): peta data survei menampilkan style lewat pilihan warna. Ekspor dan laporan dari dashboard belum.
3. **Tap langsung di layar navigasi** — default: tidak (hanya tampilan).
4. **Toleransi tap** — awal ±24 dp (setara target sentuh 48 dp), disetel ulang setelah uji di HP.
