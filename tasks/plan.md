# Rencana: Style per Feature + Select Feature dengan Tap Langsung

Status: **DRAFT — menunggu persetujuan** · Tanggal: 2026-09-30
Spec: [SPEC.md](../SPEC.md) (disetujui 2026-09-30)
Plan sebelumnya: `tasks/plan-sync-conflict.md` (arsip lokal; versi git ada di riwayat `tasks/plan.md`).

Repo: **gis-backend** @ `dev1` (T1) dan **terestria** @ `main` (T2–T11). Satu commit per task, tanpa push/deploy.

## Ringkasan

Dua fitur untuk peta project di aplikasi mobile:

1. **Style per feature.** Warna, ukuran/tebal, opacity, dan garis tepi seperti editor Layers. Diatur di bagian bawah form "Survey data" dan di layar edit, lalu ikut sync ke server.
2. **Select dengan tap langsung** pada point, line, atau polygon, menggantikan ikon info di tengah feature. Tap yang mengenai beberapa feature memunculkan daftar pilihan.

Urutan kerja: kontrak dan lapisan data dulu (backend, lalu model, DB, dan sync di mobile), kemudian tampilan dan editor style, terakhir tap langsung. Dengan urutan ini aplikasi tetap bisa dipakai di setiap titik: ikon info baru dihapus bersamaan dengan aktifnya tap langsung.

## Keputusan arsitektur

1. **`LayerStyle` dipakai ulang sebagai tipe style feature.** Properti yang disetujui sama persis (`fillColor`, `fillOpacity`, `strokeColor`, `strokeWidth`, `pointSize`), jadi editor Layers bisa dipakai bersama. Konversi ke JSON server, nilai awal dari Settings, dan clamp rentang ditaruh di `lib/models/feature_style.dart`. `LayerStyle.toJson` yang lama (warna sebagai int) tetap dipakai layer impor; format feature memakai hex `#RRGGBB`.
2. **`style == null` berarti ikut default Settings saat render.** Nilai awal editor meniru render default yang sekarang (`data_collection_screen.dart:978-1090`):

   | Geometri | Nilai awal |
   |---|---|
   | Point | `pointColor`, opacity 1.0, `pointSize` |
   | Line | `lineColor`, opacity 0.8, `lineWidth` |
   | Polygon | isi `polygonColor` dengan `polygonOpacity`, garis tepi `polygonColor`, tebal `lineWidth` |

   Feature tanpa style tampil sama persis seperti sekarang.
3. **Satu pembangun layer bersama untuk peta project dan layar navigasi** (`project_feature_layers.dart`). Kode render yang sekarang terduplikasi di `_buildMarkerCache` dan `_buildProjectDataLayers` digabung. Caching, culling, dan clustering tetap di screen.
4. **Hit-test ditulis sebagai fungsi murni di ruang layar (piksel).**
   - Tidak memakai `hitNotifier` flutter_map, supaya bisa diuji tanpa widget dan point bertumpuk ikut terdeteksi (marker hanya menangkap tap paling atas).
   - Toleransi diukur dalam dp, jadi konsisten di semua zoom. Nilai awal 24 dp, disetel lagi setelah uji di HP.
   - Point tidak lagi punya `GestureDetector` sendiri; tap diteruskan ke `onTap` peta.
   - Cluster tetap zoom-in saat diketuk.
5. **Aturan sync mengikuti SPEC §3.**
   - **Backend:** key `style` tidak ada → nilai lama dipertahankan. Ini berlaku untuk app versi lama maupun edit dari dashboard.
   - **Backend:** `null` → style dihapus.
   - **Backend:** style tidak valid → key dibuang, jadi diperlakukan seperti tidak ada. Record tetap diterima.
   - **Mobile, saat pull:** key tidak ada (backend lama) → style lokal dipertahankan.
6. **Migrasi backend `0021` ditulis manual** (satu `AddField`), karena `makemigrations` di lokal butuh koneksi DB yang diblokir. Kecocokannya dicek di CI dan di build Docker, yang menjalankan `makemigrations`; hasilnya harus kosong.
7. **Logika baru ditaruh di file terpisah.** `data_collection_screen.dart` (±4.350 baris) hanya mendapat perubahan wiring.

## Grafik dependensi

```
Fase 1 — kontrak & data
  T1 BE style (model, migrasi, validasi, serializer, to_mobile_json)
  T2 FeatureStyle + GeoData.style ──► T3 DB v7 + draft ──► T4 sync push/pull + kontrak
                                                               │  (T1 wajib ter-deploy sebelum uji sync di HP)
Fase 2 — lihat & atur style                                    ▼
  T5 pembangun layer bersama (render style) ◄── T2
  T6 editor style bersama (dari Layers) ──► T7 bagian Style di form "Survey data" (◄ T3) ──► T8 layar edit
Fase 3 — tap langsung
  T9 hit-test murni ──► T10 daftar pilihan (FeaturePickSheet) ──► T11 wiring tap + hapus ikon info (◄ T5)
```

- T1 bisa dikerjakan paralel dengan T2–T3.
- T6 dan T9 tidak saling bergantung dengan task lain di fasenya.

## Tasks

### Fase 1 — Kontrak & data

#### T1 — Backend: kolom `style` + aturan sync (gis-backend)
**Deskripsi.** `GeoData.style = JSONField(null=True, blank=True)` beserta migrasi `0021_geodata_style` (ditulis manual). Validasi dilakukan oleh `clean_style()` di `validation.py`:
- hanya 5 key;
- warna `#RRGGBB`;
- rentang `fillOpacity` 0.05–1, `strokeWidth` 0.5–10, `pointSize` 4–20.

Serializer:
- menerima `style`;
- menghapus key `style` bila tidak valid, sehingga dianggap tidak dikirim;
- `null` berarti menghapus style;
- key tidak ada berarti tidak disentuh.

`to_mobile_json` menyertakan `style`.

**Kriteria penerimaan**
- [ ] Style valid tersimpan. `to_mobile_json` mengembalikan `style` (`null` bila tidak ada).
- [ ] Update tanpa key `style` mempertahankan style lama, baik lewat push mobile maupun `partial_update` dari dashboard. Update dengan `null` menghapusnya.
- [ ] Style tidak valid tidak menggagalkan record, baik lewat `create` maupun `bulk_sync`. Style lama tetap, atau `null` untuk record baru.

**Verifikasi**
- [ ] `"$PY" -m unittest mobile.tests_feature_style` (mock, lokal): `clean_style` valid/tidak valid dan penyaringan `to_internal_value`.
- [ ] Regresi `mobile.tests_push_rules mobile.tests_pull_filter mobile.tests_photo_download`, lalu `manage.py check`.
- [ ] `mobile/tests_feature_style_db.py` (CI): create/update/partial update/null/tidak valid dengan DB nyata.

**Dependensi:** tidak ada
**File:** `mobile/models.py`, `mobile/migrations/0021_geodata_style.py` (baru), `mobile/validation.py`, `mobile/serializers.py`, `mobile/tests_feature_style.py` (baru), `mobile/tests_feature_style_db.py` (baru)
**Ukuran:** M

#### T2 — Mobile: model style feature + `GeoData.style`
**Deskripsi.** `lib/models/feature_style.dart` berisi:
- `featureStyleToJson(LayerStyle?)` (hex);
- `featureStyleFromJson(Object?)`: `null` bila tidak valid, nilai di-clamp, key asing diabaikan;
- `defaultFeatureStyle(GeometryType, AppSettings)` sesuai keputusan #2.

`GeoData` mendapat `style` (`LayerStyle?`) pada `toJson`/`fromJson` (format lokal dan server) serta `copyWith(style:, clearStyle:)`.

**Kriteria penerimaan**
- [ ] Round-trip hex tidak berubah. Warna/tipe tidak valid → `null`. Nilai di luar rentang di-clamp.
- [ ] Nilai awal per geometri sama dengan render default sekarang.
- [ ] `GeoData` tanpa style: `toJson`/`fromJson` identik dengan sekarang, sehingga test lama tetap hijau.

**Verifikasi**
- [ ] `flutter test test/models/feature_style_test.dart test/models/geo_data_style_test.dart`.
- [ ] `flutter test` penuh (641 + baru).
- [ ] `flutter analyze` tanpa warning baru (baseline 29).

**Dependensi:** tidak ada
**File:** `lib/models/feature_style.dart` (baru), `lib/models/geo_data_model.dart`, `test/models/feature_style_test.dart` (baru), `test/models/geo_data_style_test.dart` (baru)
**Ukuran:** M

#### T3 — Mobile: DB v7 + draft menyimpan style
**Deskripsi.**
- `_databaseVersion = 7`.
- Kolom `geo_data.style TEXT` di tabel baru, ditambah migrasi `oldVersion < 7` yang idempoten memakai pola `missingColumns`.
- `geoDataToRow`/`geoDataFromRow` menulis dan membaca JSON style.
- `CollectionDraft` mendapat `style`.

**Kriteria penerimaan**
- [ ] DB baru punya kolom `style`.
- [ ] Upgrade v6 → v7 mempertahankan semua record dengan `style = null`. Menjalankan migrasi dua kali tidak error.
- [ ] Style tersimpan dan terbaca kembali utuh.
- [ ] Draft menyimpan dan mengembalikan style. Draft lama tanpa key `style` tetap terbaca.

**Verifikasi**
- [ ] `flutter test test/services/db_v7_test.dart` (pola `db_v6_test.dart`, sqflite ffi) dan test draft.
- [ ] `flutter test` penuh, `flutter analyze`.

**Dependensi:** T2
**File:** `lib/services/database_service.dart`, `lib/services/collection_draft_service.dart`, `test/services/db_v7_test.dart` (baru), test draft yang ada (ditambah kasus)
**Ukuran:** M

#### T4 — Mobile: sync push/pull style + kontrak
**Deskripsi.**
- `buildGeoDataPayload` **selalu** mengirim `style` (objek atau `null`).
- Pull untuk record baru atau yang lebih baru di server: pakai `style` server bila key-nya ada; bila tidak ada, pertahankan style lokal.
- `resolveUseServer` (konflik) mengikuti aturan yang sama.
- `docs/sync-push-contract.md` mendapat bagian `style`.

**Kriteria penerimaan**
- [ ] Payload berisi `style` objek untuk record custom dan `null` untuk default.
- [ ] Pull dengan `style` objek → tersimpan. Dengan `null` → dihapus. Tanpa key → style lokal tetap.
- [ ] "Use server version" membawa style server.

**Verifikasi**
- [ ] `flutter test test/services/sync_feature_style_test.dart` (fake HTTP dan storage, pola `sync_conflict_test.dart`).
- [ ] `flutter test` penuh, `flutter analyze`.

**Dependensi:** T2, T3. T1 harus ter-deploy di dev sebelum uji di HP.
**File:** `lib/services/sync_service.dart`, `docs/sync-push-contract.md`, `test/services/sync_feature_style_test.dart` (baru)
**Ukuran:** M

### Checkpoint A — lapisan data selesai
- [ ] Semua test hijau: backend lokal, `flutter test`, `flutter analyze` tanpa warning baru.
- [ ] Belum ada perubahan yang terlihat user.
- [ ] Backend T1 sudah di dev bila ingin menguji sync di HP.

### Fase 2 — Lihat & atur style

#### T5 — Mobile: render style per feature (peta project + navigasi)
**Deskripsi.** File baru `lib/widgets/map/project_feature_layers.dart`:
- `effectiveFeatureStyle(data, geometryType, settings)`;
- pembangun marker/polyline/polygon untuk satu `GeoData`.

Dipakai oleh `_buildMarkerCache` (peta project) dan `_buildProjectDataLayers` (navigasi). Ikon info masih dipertahankan; baru dihapus di T11.

**Kriteria penerimaan**
- [ ] Feature dengan style custom tampil dengan warna, opacity, tebal, dan ukuran miliknya di kedua layar.
- [ ] Feature tanpa style tampil **sama persis** dengan sekarang.
- [ ] Caching, culling, dan clustering tidak berubah.

**Verifikasi**
- [ ] `flutter test test/widgets/project_feature_layers_test.dart`: warna/opacity/tebal polyline dan polygon serta ukuran/warna marker, untuk kasus custom maupun default.
- [ ] `flutter test`, `flutter analyze`.
- [ ] Manual: peta project dan navigasi dengan data campuran.

**Dependensi:** T2
**File:** `lib/widgets/map/project_feature_layers.dart` (baru), `lib/screens/data_collection/data_collection_screen.dart`, `lib/screens/navigation/navigation_screen.dart`, `test/widgets/project_feature_layers_test.dart` (baru)
**Ukuran:** M

#### T6 — Mobile: editor style bersama (diekstrak dari Layers)
**Deskripsi.** `lib/widgets/style/style_editor.dart` berisi `StyleEditorFields` (warna, slider per geometri, pemilih warna) dan `StylePreview`, dipindahkan dari `_StyleEditorSheet` di `layers_screen.dart`. LayersScreen memakai widget bersama ini **tanpa perubahan perilaku**.

**Kriteria penerimaan**
- [ ] Kontrol per geometri sama seperti sekarang:
  - point: warna, opacity, ukuran;
  - line: warna, opacity, tebal;
  - polygon: warna isi, warna garis tepi, opacity, tebal.
- [ ] Pratinjau berubah langsung.
- [ ] Editor layer (tambah/edit layer) tetap berjalan seperti sebelumnya.

**Verifikasi**
- [ ] `flutter test test/widgets/style_editor_test.dart`: kontrol per geometri, slider memanggil `onChanged`, lebar 360 dp tanpa overflow.
- [ ] `flutter test`, `flutter analyze`.
- [ ] Manual: edit style layer impor.

**Dependensi:** tidak ada
**File:** `lib/widgets/style/style_editor.dart` (baru), `lib/screens/layers/layers_screen.dart`, `test/widgets/style_editor_test.dart` (baru)
**Ukuran:** S–M

#### T7 — Mobile: bagian "Style" di form "Survey data"
**Deskripsi.** `lib/widgets/style/feature_style_section.dart`:
- saat tertutup menampilkan ringkasan: "Default", atau swatch plus ringkasan singkat;
- saat dibuka menampilkan `StyleEditorFields` sesuai geometri project;
- tombol "Use default".

Di `data_collection_screen.dart`:
- state `_featureStyle`;
- bagian Style dipasang di bawah `DynamicForm`;
- `_saveData` menyimpan style;
- **"Save & next" mempertahankan style**;
- draft menyimpan dan memulihkan style.

**Kriteria penerimaan**
- [ ] Mengubah style lalu Save membuat feature baru tersimpan dengan style itu dan tampil sesuai style di peta (T5). Tanpa diubah, `style = null`.
- [ ] "Save & next" membawa style ke data berikutnya. Membuka project lagi mulai dari default.
- [ ] Menutup form, lalu kembali atau restart saat ada draft, tidak menghilangkan style.

**Verifikasi**
- [ ] `flutter test test/widgets/feature_style_section_test.dart`:
  - tertutup menampilkan "Default";
  - mengubah warna memanggil `onChanged`;
  - "Use default" menghasilkan `null`;
  - 360 dp tanpa overflow.
- [ ] `flutter test`, `flutter analyze`.
- [ ] Manual: koleksi point, line, dan polygon dengan style berbeda.

**Dependensi:** T3, T5, T6
**File:** `lib/widgets/style/feature_style_section.dart` (baru), `lib/screens/data_collection/data_collection_screen.dart`, `test/widgets/feature_style_section_test.dart` (baru)
**Ukuran:** M

#### T8 — Mobile: ubah/reset style di layar edit data
**Deskripsi.** `EditGeoDataScreen` menampilkan `FeatureStyleSection` dengan style record. Saat disimpan: `copyWith(style / clearStyle)`, `isSynced: false`, `updatedAt` baru (seperti edit atribut sekarang).

**Kriteria penerimaan**
- [ ] Style bisa diganti atau di-reset dari layar edit.
- [ ] Setelah disimpan, record jadi "belum sync" dan style baru tampil di peta.
- [ ] Record lain tidak tersentuh.

**Verifikasi**
- [ ] Widget test layar edit dengan fake storage: ubah style lalu Save → yang tersimpan punya style dan `isSynced == false`.
- [ ] `flutter test`, `flutter analyze`.

**Dependensi:** T7
**File:** `lib/screens/project/edit_geo_data_screen.dart`, `test/widgets/edit_geo_data_style_test.dart` (baru)
**Ukuran:** S

### Checkpoint B — style bisa diatur & terlihat
- [ ] Semua test hijau.
- [ ] Manual di HP: atur style saat koleksi dan saat edit, lihat di peta project dan navigasi, sync, lalu pull di HP kedua memunculkan style yang sama. Syarat: backend T1 sudah di dev.

### Fase 3 — Tap langsung

#### T9 — Mobile: hit-test murni
**Deskripsi.** `lib/services/map/feature_hit_test.dart` menerima posisi tap, bentuk feature dalam koordinat layar (point, line, polygon), dan toleransi dalam piksel. Hasilnya daftar feature yang kena, diurutkan:
1. point, dari yang terdekat;
2. line, dari yang terdekat;
3. polygon, dari yang terkecil.

Ada juga helper untuk membangun bentuk dari `GeoData` lewat callback proyeksi `LatLng → Offset`, sehingga bisa diuji tanpa peta.

**Kriteria penerimaan**
- [ ] Point kena bila jarak ≤ radius marker + toleransi.
- [ ] Line kena bila jarak ke segmen ≤ toleransi.
- [ ] Polygon kena bila tap di dalam area (ray casting) atau ≤ toleransi dari garis tepi.
- [ ] Beberapa hit → semua dikembalikan dengan urutan stabil. Tidak ada hit → kosong.
- [ ] Geometri rusak (line 1 titik, polygon < 3 titik) diabaikan tanpa error.

**Verifikasi**
- [ ] `flutter test test/services/feature_hit_test_test.dart` (unit murni).
- [ ] `flutter analyze`.

**Dependensi:** tidak ada
**File:** `lib/services/map/feature_hit_test.dart` (baru), `test/services/feature_hit_test_test.dart` (baru)
**Ukuran:** S

#### T10 — Mobile: daftar pilihan saat tap mengenai beberapa feature
**Deskripsi.**
- `lib/widgets/map/feature_pick_sheet.dart`: bottom sheet berisi daftar feature yang kena. Setiap item menampilkan judul record, swatch style efektif, dan ikon geometri; memilih satu mengembalikan `GeoData` tersebut.
- Judul memakai helper bersama `recordTitle()`. Helper ini diekstrak dari `GeoDataListItem._getTitle()`: nilai field non-foto pertama, fallback "Survey Data #id8". `GeoDataListItem` ikut memakainya.

**Kriteria penerimaan**
- [ ] Semua hit tampil sesuai urutan T9, dengan judul dan swatch yang benar.
- [ ] Tap item mengembalikan record itu. Menutup sheet mengembalikan `null`.
- [ ] Judul di daftar data tidak berubah.

**Verifikasi**
- [ ] `flutter test test/widgets/feature_pick_sheet_test.dart` (360 dp tanpa overflow) dan test `recordTitle`.
- [ ] Test `GeoDataListItem` yang ada tetap hijau. `flutter analyze`.

**Dependensi:** T5 (style efektif), T9 (urutan)
**File:** `lib/widgets/map/feature_pick_sheet.dart` (baru), `lib/utils/record_title.dart` (baru), `lib/widgets/geo_data_list_item.dart`, `test/widgets/feature_pick_sheet_test.dart` (baru)
**Ukuran:** S–M

#### T11 — Mobile: wiring tap langsung + hapus ikon info
**Deskripsi.** `_onMapTap` di peta project mengikuti urutan:
1. alat ukur aktif → titik ukur;
2. mode gambar (bukan tracking) → tambah titik;
3. selain itu → hit-test feature yang **terlihat**, diproyeksikan dengan `_mapController.camera`:
   - 0 hit → tidak terjadi apa-apa;
   - 1 hit → `_showDataDetail`;
   - lebih dari 1 → `FeaturePickSheet`, lalu detail.

Point tidak lagi memakai `GestureDetector` sendiri, sedangkan cluster tetap zoom-in. Ikon info line/polygon dihapus dari pembangun bersama (T5), sehingga berlaku di peta project dan navigasi.

**Kriteria penerimaan**
- [ ] Tap pada line (dalam toleransi), di dalam polygon, atau pada point membuka detail. Ikon info tidak ada lagi di kedua layar.
- [ ] Polygon bertumpuk atau point bertumpuk → daftar pilihan muncul.
- [ ] Alat ukur dan mode gambar tetap memakai tap untuk menambah titik. Saat tracking, tap tetap bisa memilih feature.
- [ ] Tap di area kosong tidak melakukan apa-apa.

**Verifikasi**
- [ ] Test pembangun layer diperbarui: tidak ada marker info untuk line/polygon, dan point tanpa `GestureDetector`.
- [ ] `flutter test`, `flutter analyze`.
- [ ] Manual di HP: line tipis, polygon kecil/besar/bertumpuk, point rapat, zoom rendah (cluster), mode gambar, dan alat ukur.

**Dependensi:** T5, T9, T10
**File:** `lib/screens/data_collection/data_collection_screen.dart`, `lib/widgets/map/project_feature_layers.dart`, `test/widgets/project_feature_layers_test.dart`
**Ukuran:** M

### Checkpoint C — selesai
- [ ] Semua kriteria SPEC §9 terpenuhi.
- [ ] `flutter test` hijau dan `flutter analyze` tanpa warning baru. Unittest backend dan `manage.py check` bersih, test DB lulus di CI.
- [ ] Uji di HP:
  - upgrade dari versi sebelumnya (v6 → v7) tanpa kehilangan data;
  - style ikut sync ke HP kedua;
  - app versi lama tetap bisa push tanpa menghapus style;
  - edit dari web dashboard tidak menghapus style;
  - ketepatan dan kenyamanan tap (toleransi disetel bila perlu).
- [ ] Urutan rilis: deploy backend (T1) **sebelum** rilis app.

## Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| `data_collection_screen.dart` sangat besar | Sedang | Logika baru di file terpisah (T5, T7, T9, T10); screen hanya wiring |
| Tap kurang tepat di HP (line tipis, jari besar) | Sedang | Toleransi dalam dp, mulai 24 dp (target sentuh 48 dp); jadi konstanta yang mudah disetel; uji manual di Checkpoint C |
| Menghapus `GestureDetector` di point membuat tap tidak sampai ke peta | Sedang | Tanpa recognizer di marker, tap diteruskan ke `onTap` FlutterMap; diuji manual di T11; cluster tetap punya `GestureDetector` |
| App baru bicara dengan backend lama (T1 belum deploy) | Sedang | Backend lama mengabaikan `style`; pull tanpa key mempertahankan style lokal (T4); deploy T1 lebih dulu |
| App lama menimpa style saat push | Sedang | Backend: key tidak ada → dipertahankan (T1, diuji) |
| Style rusak memblokir sync | Tinggi | Tidak valid → dibuang, record diterima (T1); mobile meng-clamp sebelum kirim (T2) |
| Migrasi DB v7 di perangkat | Sedang | Idempoten + test upgrade v6 → v7 (T3) |
| Hit-test lambat dengan data banyak | Rendah | Hanya feature yang terlihat (culling yang ada), O(jumlah vertex), dipanggil hanya saat tap |
| Refactor editor Layers mengubah perilaku | Rendah | T6 murni ekstraksi + widget test + cek manual |

## Pertanyaan terbuka
Tidak ada yang menghalangi. Default dari SPEC §10 dipakai: ekspor dan web dashboard di tahap berikutnya, tap langsung tidak di layar navigasi, toleransi awal 24 dp.
