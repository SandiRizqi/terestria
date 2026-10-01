# Rencana: Perbaikan hasil review + pilihan warna peta di web

Status: **disetujui user (2026-10-01)**; pertanyaan terbuka memakai default · Tanggal: 2026-10-01
Spec: [SPEC.md](../SPEC.md) (disetujui 2026-09-30). Bagian yang berubah tercantum di "Perubahan SPEC" dan diterapkan di commit persiapan setelah plan ini disetujui.
Plan sebelumnya: `tasks/plan-feature-style.md` (arsip lokal; versi git ada di riwayat `tasks/plan.md`). Item manual yang belum selesai dari plan itu dibawa ke `tasks/todo.md`.

Satu commit per task per repo, tanpa push/deploy. Status semua task dicatat di `tasks/todo.md` (terestria).

| Repo | Branch | Task |
|---|---|---|
| gis-backend | `dev1` | T1, T2 (validasi), T3 |
| terestria | `main` | T2 (model), T4–T8 |
| gis-dashboard | `dev1` | T9 |

## Ringkasan

1. **Perbaikan hasil review** build style per feature + tap langsung (terestria `d44caea..b0a854b`, backend `d54d508`): 1 kritis, 3 penting, 2 saran, dan kode mati.
2. **Fitur baru di web dashboard:** user memilih warna peta data survei, yaitu **Status verifikasi** (seperti sekarang) atau **Style feature** dari aplikasi mobile. Legenda selalu menyebut mode yang aktif, jadi jelas warna di peta berasal dari status atau dari style.

Urutan kerja: backend dulu, karena kontrak style ikut berubah dan semuanya harus masuk sebelum `d54d508` di-deploy. Lalu mobile, terakhir dashboard (butuh tile dari T3).

## Keputusan arsitektur

1. **Verifikasi hanya di-reset kalau isi record berubah** (`GeoDataSerializer.update`).
   - Yang dibandingkan dengan nilai tersimpan: **isian form non-foto** (persis sama) dan **koordinat titik** (urutan latitude/longitude, dibandingkan sebagai angka).
   - **Foto tidak dibandingkan** (keputusan user 2026-10-01). Menambah, mengganti, atau menghapus foto tidak me-reset verifikasi. Field foto dikenali dari tipe field project (`photo`), dengan cadangan dari bentuk nilainya (daftar objek ber-`serverKey`/`localPath`) dan key lama `*_oss_urls`/`*_oss_keys`.
   - Kalau yang berubah hanya style (atau data dikirim ulang tanpa perubahan), status verifikasi, `verified_by`/`verified_at`, error validasi, dan `schema_snapshot` tidak berubah. `updated_at` tetap naik supaya HP lain menarik perubahannya.
   - Create tidak berubah (selalu divalidasi).
   - Ini mengubah aturan backend di luar `style` (SPEC "Ask first"); diminta user lewat perbaikan ini.
2. **Kontrak style direvisi selagi belum ada yang ter-deploy.**
   - `pointSize` **10–24** (sebelumnya 4–20). Rentang ini persis memetakan diameter marker 20–48 dp di HP, jadi setiap langkah slider terlihat. Semua nilai Settings (8–24) muat; 8–9 memang sudah tampil 20 dp, sama dengan 10.
   - Key asing **diabaikan** (5 key inti tetap wajib), supaya app versi baru bisa menambah properti tanpa style-nya dibuang oleh backend versi ini.
   - Mobile men-clamp saat membaca, jadi style uji coba yang terlanjur tersimpan dengan nilai < 10 tetap terbaca.
3. **Editor style menerima batas dari pemanggil.** Layers tetap 4–20 dengan pratinjau lamanya. Style feature memakai 10–24, dan pratinjau point = diameter marker di peta.
4. **Hit-test dua tingkat.**
   - Tingkat 1, "kena langsung": tap di dalam lingkaran marker, di atas garis (setengah tebal garis + 4 dp), atau di dalam polygon.
   - Tingkat 2, hanya bila tingkat 1 kosong: dalam toleransi 24 dp.
   - Urutan di dalam tingkat tetap: point terdekat → line terdekat → polygon terkecil. Daftar pilihan tetap muncul untuk feature yang benar-benar bertumpuk.
5. **Yang tergambar = yang bisa diketuk.** Culling tampilan line/polygon memakai aturan bbox yang sama dengan hit-test. Bbox dihitung sekali setiap data dimuat.
6. **Warna peta web dipilih user.**
   - Pilihan `Status verifikasi` | `Style feature`. Default Status (perilaku sekarang), diingat per browser lewat localStorage (aman bila tidak tersedia).
   - Tile (MVT) membawa 5 properti datar: `style_fill_color`, `style_fill_opacity`, `style_stroke_color`, `style_stroke_width`, `style_point_size`. Properti ini tidak ada bila feature tanpa style. Mode GeoJSON (cadangan) mengisi properti yang sama dari `data.style`.
   - Feature tanpa style memakai **default pabrik aplikasi**: point `#2196F3`; line `#4CAF50` α 0.8 tebal 3; polygon isi `#FF9800` α 0.3, tepi `#FF9800` tebal 3. Settings tiap HP bisa berbeda dan tidak dikirim ke server, jadi web tidak bisa meniru Settings masing-masing HP.
   - Ukuran point di mode Style = `pointSize × ⅔` px (default 12 → 8 px, sama dengan sekarang). Tepi polygon α 0.85 seperti di HP.
   - Filter verifikasi dan sorotan merah feature terpilih tetap berlaku di kedua mode.
   - Logika warna (expression MapLibre, default, isi legenda) ditaruh di modul murni `mapColorMode.ts` yang dites. Pilihan + legenda di komponen baru, sehingga `ProjectMapView.tsx` (±1.900 baris) hanya mendapat wiring.
7. **Tile lama tanpa style tidak tersaji setelah deploy.**
   - Key cache OSS mendapat segmen versi: `tiles/project_{id}/s2/…`. Segmen ini masih di bawah prefix invalidasi yang sama, jadi tile lama ikut terhapus saat invalidasi berikutnya.
   - URL tile di dashboard mendapat `sv=2` untuk melewati cache browser (1 jam).

## Grafik dependensi

```
Fase 1 — backend (sebelum deploy d54d508)
  T1 verifikasi tetap bila isi tidak berubah
  T2 kontrak style: pointSize 10–24, key asing diabaikan (backend + model mobile)
  T3 tile MVT membawa style + versi cache tile
Fase 2 — mobile
  T4 editor ukuran point = ukuran di peta ◄── T2
  T5 hit-test dua tingkat
  T6 culling tampilan = aturan hit-test ──► T7 hapus kode mati layer ikon (file sama)
  T8 Style di sheet "Tracking Aktif" (opsional, lihat pertanyaan terbuka)
Fase 3 — web dashboard
  T9 pilihan warna peta + legenda ◄── T3 (mode vector tile)
```

- T1, T2, dan T3 saling bebas. T5, T6, dan T8 juga saling bebas.

## Tasks

### Fase 1 — Backend (semua sebelum `d54d508` di-deploy)

#### T1 — Verifikasi tidak di-reset bila isi record tidak berubah (gis-backend) — kritis
**Deskripsi.** Fungsi murni `ingest_content_changed(form_fields, old_form_data, new_form_data, old_points, new_points)` di `validation.py`, mengikuti aturan di Keputusan 1. `GeoDataSerializer.update` hanya memanggil `_apply_ingest_verification` bila fungsi itu mengembalikan `True`. `updated_at` selalu naik.

**Kriteria penerimaan**
- [ ] Record verified, lalu update style saja → `verification_status`, `verified_by`, `verified_at`, `validation_errors`, dan `schema_snapshot` tidak berubah. `style` dan `updated_at` berubah.
- [ ] Data dikirim ulang persis sama → verifikasi tetap.
- [ ] Hanya foto yang berubah (ditambah, diganti, dihapus, atau beda `serverUrl`/`localPath`) → verifikasi tetap.
- [ ] Verifikasi di-reset seperti sekarang bila salah satu terjadi:
  - nilai field non-foto berubah;
  - field non-foto ditambah atau dihapus;
  - koordinat titik berubah, bertambah, atau berkurang.
- [ ] Create tidak berubah. Test lama `test_update_mereset_verifikasi` tetap lulus.

**Verifikasi**
- [ ] Lokal: `"$PY" -m unittest mobile.tests_verification_keep` (baru, murni), semua test lokal lain, dan `"$PY" manage.py check`.
- [ ] CI (test DB):
  - record verified lalu push style saja lewat `create` (upsert) → tetap verified;
  - push dengan isian berubah → di-reset.

**Dependensi:** tidak ada.
**File:** `mobile/validation.py`, `mobile/serializers.py`, `mobile/tests_verification_keep.py` (baru), `mobile/tests_feature_style_db.py`.
**Ukuran:** S–M.

#### T2 — Kontrak style direvisi: `pointSize` 10–24, key asing diabaikan (gis-backend + terestria)
**Deskripsi.**
- Backend `clean_style`: rentang `pointSize` 10–24. Key di luar 5 key inti dibuang, bukan membuat seluruh style ditolak. 5 key inti tetap wajib.
- Mobile `feature_style.dart`: `featureMinPointSize = 10`, `featureMaxPointSize = 24`.
- Dokumen kontrak diperbarui.

**Kriteria penerimaan**
- [ ] Backend: `pointSize` 10 dan 24 diterima. 9 dan 25 → style dibuang, record tetap diterima.
- [ ] Backend: style dengan key asing (mis. `dash`) → tersimpan tanpa key itu. Salah satu key inti hilang → style dibuang.
- [ ] Mobile: nilai di-clamp ke 10–24 saat dibaca dan dikirim. Dengan Settings `pointSize` 24, mengganti warna saja tidak mengecilkan point.
- [ ] Render default (tanpa style) tetap identik; test lama lulus.
- [ ] `docs/sync-push-contract.md` §4 memuat rentang dan aturan key asing yang baru.

**Verifikasi**
- [ ] Backend: `"$PY" -m unittest mobile.tests_feature_style` dan `manage.py check`.
- [ ] Mobile: `flutter test test/models/feature_style_test.dart`, lalu `flutter test` penuh dan `flutter analyze` (baseline).

**Dependensi:** tidak ada.
**File:** gis-backend `mobile/validation.py`, `mobile/tests_feature_style.py`; terestria `lib/models/feature_style.dart`, `test/models/feature_style_test.dart`, `docs/sync-push-contract.md`.
**Ukuran:** S.

#### T3 — Tile peta web membawa style (gis-backend)
**Deskripsi.**
- Migrasi `0022_geodata_tile_add_style` (RunSQL) mengganti fungsi `get_geodata_tile` dengan 5 kolom style dari `gd.style`. Angka hanya diambil bila bertipe number, supaya data rusak tidak menggagalkan tile.
- Reverse = fungsi versi 0020.
- `_build_tile_cache_key` mendapat segmen versi `s2`.

**Kriteria penerimaan**
- [ ] Tile record ber-style memuat 5 properti style; record tanpa style tidak memuatnya.
- [ ] Nilai style yang bukan tipe yang diharapkan tidak membuat pembuatan tile gagal.
- [ ] Migrasi bisa dibalik ke fungsi versi 0020.
- [ ] Key cache baru `tiles/project_{id}/s2/{z}/{x}/{y}.pbf` (group sama). `invalidate_tile_cache` tetap menghapus key lama maupun baru.

**Verifikasi**
- [ ] Lokal:
  - `"$PY" -m unittest mobile.tests_tile_style` (key cache, isi SQL migrasi dan reverse);
  - cek graf migrasi offline (0022 → 0021);
  - `manage.py check`.
- [ ] CI: `mobile.tests_tile_style_db`. `_generate_tile_from_db` untuk record ber-style memuat `style_fill_color` dan `#FF9800`.

**Dependensi:** tidak ada (kolom `style` sudah ada dari `d54d508`).
**File:** `mobile/migrations/0022_geodata_tile_add_style.py`, `mobile/views.py`, `mobile/tests_tile_style.py`, `mobile/tests_tile_style_db.py`.
**Ukuran:** S–M.

### Checkpoint A — backend siap deploy
- [ ] Semua test lokal backend hijau, `manage.py check` bersih, dan migrasi 0021 + 0022 konsisten (cek offline).
- [ ] Test mobile T2 hijau; `flutter analyze` sesuai baseline.
- [ ] (User) CI lulus: `tests_feature_style_db`, `tests_photo_download_db`, `tests_verification`, `tests_tile_style_db`.

### Fase 2 — Mobile

#### T4 — Editor ukuran point = ukuran di peta (terestria)
**Deskripsi.** `StyleEditorFields` menerima batas dari pemanggil: rentang slider dan cara menghitung diameter point untuk pratinjau. Layers memakai batas lama (4–20, pratinjau lama). Bagian Style feature memakai 10–24, dan pratinjaunya memakai `featurePointDiameter`.

**Kriteria penerimaan**
- [ ] Form "Survey data" dan layar edit: slider ukuran point 10–24 (14 langkah); tiap langkah mengubah diameter marker di peta (20–48 dp).
- [ ] Pratinjau point berdiameter sama dengan marker di peta.
- [ ] Editor Layers: rentang, langkah, dan pratinjau tidak berubah (test regresi).
- [ ] Muat di 360 dp tanpa overflow.

**Verifikasi:** `flutter test test/widgets/style_editor_test.dart test/widgets/feature_style_section_test.dart`, `flutter test` penuh, `flutter analyze` (baseline).
**Dependensi:** T2.
**File:** `lib/widgets/style/style_editor.dart`, `lib/widgets/style/feature_style_section.dart`, `lib/screens/layers/layers_screen.dart`, `test/widgets/style_editor_test.dart`, `test/widgets/feature_style_section_test.dart`.
**Ukuran:** M.

#### T5 — Tap: yang kena langsung didahulukan (terestria)
**Deskripsi.** Hit-test dua tingkat (Keputusan 4). `HitLine` membawa setengah tebal garis dari style feature.

**Kriteria penerimaan**
- [ ] Dua polygon bersebelahan (84 dp): tap di dalam A, 20 dp dari tepi bersama → hanya A. Pada grid 3×3, tap di dalam blok tengah tidak memunculkan daftar pilihan.
- [ ] Tap tepat di point P1 dengan point lain 30 dp di sebelahnya → hanya P1. Tap di antara dua point (tidak tepat di salah satunya) → keduanya.
- [ ] Polygon yang benar-benar bertumpuk (yang kecil di dalam yang besar) → keduanya, terkecil dulu (seperti sekarang).
- [ ] Tap di luar semua polygon, ≤ 24 dp dari tepi salah satunya → polygon itu.
- [ ] Tap di atas garis A dengan garis B 20 dp di sebelahnya → hanya A.

**Verifikasi:** `flutter test test/services/feature_hit_test_test.dart test/widgets/project_features_at_tap_test.dart`, `flutter test` penuh, `flutter analyze`.
**Dependensi:** tidak ada.
**File:** `lib/services/map/feature_hit_test.dart`, `lib/widgets/map/project_feature_layers.dart`, `test/services/feature_hit_test_test.dart`, `test/widgets/project_features_at_tap_test.dart`.
**Ukuran:** S–M.

#### T6 — Yang tergambar = yang bisa diketuk (terestria)
**Deskripsi.**
- Helper publik di `project_feature_layers.dart` untuk mengecek irisan bbox feature dengan area peta, dipakai bersama oleh hit-test dan culling.
- `_buildMarkerCache` menghitung bbox tiap line/polygon sekali.
- `_updateVisibleLayers` memakai helper itu, menggantikan aturan "ada titik sudut di area".

**Kriteria penerimaan**
- [ ] Polygon yang menutupi seluruh layar (semua titik sudut di luar area + buffer) tetap tergambar. Feature yang sepenuhnya di luar area tidak tergambar.
- [ ] Line panjang yang melintasi layar dengan kedua ujung jauh tetap tergambar.
- [ ] Point dan clustering tidak berubah.
- [ ] Bbox tidak dihitung ulang setiap peta digeser; cukup saat data dimuat.

**Verifikasi:** test helper di `test/widgets/project_feature_layers_test.dart`, `flutter test` penuh, `flutter analyze`. Manual: zoom 18 di tengah blok besar → blok tetap tampil dan bisa diketuk.
**Dependensi:** tidak ada.
**File:** `lib/widgets/map/project_feature_layers.dart`, `lib/screens/data_collection/data_collection_screen.dart`, `test/widgets/project_feature_layers_test.dart`.
**Ukuran:** S.

#### T7 — Hapus kode mati layer ikon line/polygon (terestria)
**Deskripsi.** Hapus cabang `MarkerLayer(_visibleMarkers)` untuk line/polygon di `_buildExistingDataLayers` beserta komentar "tap targets"-nya. Sejak T11, marker hanya ada untuk point.

**Kriteria penerimaan**
- [ ] Tidak ada perubahan perilaku; `flutter analyze` tanpa warning baru; test hijau.

**Verifikasi:** `flutter test`, `flutter analyze`.
**Dependensi:** T6 (file sama, supaya tidak konflik).
**File:** `lib/screens/data_collection/data_collection_screen.dart`.
**Ukuran:** XS.

#### T8 — Style di sheet "Tracking Aktif" (terestria) — opsional
**Deskripsi.** `AttributeFormSheet` (stop & save dari panel Tracking Aktif) menampilkan `FeatureStyleSection`, dan `buildGeoData` menerima `style`.

**Kriteria penerimaan**
- [ ] Sheet menampilkan bagian Style (saat tertutup: "Default").
- [ ] Style diubah → record tersimpan membawa style. Tidak diubah → `null`.
- [ ] Muat di 360 dp.

**Verifikasi:** `flutter test test/services/tracking/session_to_geodata_test.dart test/widgets/attribute_form_sheet_test.dart`, `flutter test` penuh, `flutter analyze`.
**Dependensi:** tidak ada.
**File:** `lib/widgets/tracking/attribute_form_sheet.dart`, `lib/services/tracking/session_to_geodata.dart`, `test/services/tracking/session_to_geodata_test.dart`, `test/widgets/attribute_form_sheet_test.dart` (baru).
**Ukuran:** S.

### Checkpoint B — mobile
- [ ] `flutter test` hijau (714 + test baru); `flutter analyze` 0 error / 29 warning.
- [ ] (User, di HP)
  - tap pada blok bersebelahan langsung membuka detailnya;
  - polygon bertumpuk memunculkan daftar pilihan;
  - slider ukuran point terlihat efeknya, dan pratinjau sama dengan di peta;
  - zoom dekat di tengah blok besar → blok tampil dan bisa diketuk;
  - Style di sheet Tracking Aktif.

### Fase 3 — Web dashboard

#### T9 — Pilihan warna peta: Status verifikasi / Style feature (gis-dashboard)
**Deskripsi.** Di peta data survei (`ProjectMapView`, mode project dan group): pilihan **Warna peta** dengan dua opsi, legenda sesuai mode, dan pilihan diingat per browser. Aturan warna mengikuti Keputusan 6.

**Kriteria penerimaan**
- [ ] Ganti mode langsung mengubah warna point/line/polygon tanpa memuat ulang halaman. Berlaku di mode vector tile maupun GeoJSON, project maupun group.
- [ ] Mode Status sama persis dengan sekarang.
- [ ] Mode Style: record ber-style tampil dengan warna, opacity, tebal, dan ukuran dari style-nya. Record tanpa style memakai default pabrik aplikasi.
- [ ] Legenda menyebut mode aktif ("Warna: Status verifikasi" / "Warna: Style feature"). Di mode Style, legenda menampilkan contoh "Default (tanpa style)".
- [ ] Filter verifikasi tetap bekerja di kedua mode; feature terpilih tetap merah.
- [ ] Pilihan bertahan setelah reload. Bila localStorage tidak tersedia → Status.
- [ ] URL tile memakai `sv=2`.

**Verifikasi**
- [ ] `npm test` dengan test baru `mapColorMode.test.mjs`:
  - expression per mode dan per layer;
  - nama properti sama dengan kolom tile T3;
  - warna default dan ukuran point;
  - baca/simpan pilihan.
- [ ] `npx tsc --noEmit` sama dengan baseline (1 error lama); `next lint` per file tanpa masalah baru.
- [ ] Manual di browser (setelah backend T3 ter-deploy di dev): project point/line/polygon dan group; ganti mode, reload, dan filter.

**Dependensi:** T3 untuk mode vector tile (mode GeoJSON bisa jalan tanpa T3).
**File:** `components/mobilesurveyproject/mapColorMode.ts` (baru), `components/mobilesurveyproject/mapColorMode.test.mjs` (baru), `components/mobilesurveyproject/components/MapColorLegend.tsx` (baru), `components/mobilesurveyproject/ProjectMapView.tsx`, `components/mobilesurveyproject/types.ts`.
**Ukuran:** M.

### Checkpoint C — selesai
- [ ] Di ketiga repo, semua test lokal hijau dan baseline analyze/tsc/lint tidak memburuk.
- [ ] (User) Test DB backend lulus di CI; uji manual Checkpoint B dan T9 selesai.
- [ ] Urutan deploy di bawah dijalankan.

## Urutan deploy (oleh user)
1. gis-backend `dev1`: `d54d508` + T1–T3 → CI hijau → deploy (migrasi `0021`, `0022`).
2. gis-dashboard (T9), setelah backend.
3. Rilis aplikasi mobile, setelah backend.

## Perubahan SPEC (diterapkan di commit persiapan setelah plan disetujui)
- §1 Keputusan: web dashboard menampilkan style lewat pilihan warna peta. Ekspor dan PDF tetap belum.
- §3: `pointSize` 10–24; key asing diabaikan (5 key inti wajib); aturan verifikasi (perubahan style atau foto saja tidak me-reset verifikasi).
- §7: test hit-test dua tingkat.
- §9, kriteria baru:
  - (12) perubahan style atau foto saja tidak mengubah verifikasi;
  - (13) tap di dalam satu blok yang bersebelahan dengan blok lain langsung membuka detailnya;
  - (14) peta web punya pilihan warna dengan legenda yang menyebut mode aktif.
- §10: pertanyaan 2 (web dashboard) terjawab sebagian.

## Risiko

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Perbandingan isi menganggap "sama" padahal isi berubah, sehingga verifikasi lama tetap berlaku | Tinggi | Field non-foto dibandingkan persis; format yang tidak dikenal dianggap berubah; test per kasus |
| Perbandingan menganggap "berubah" padahal sama (format angka/tanggal berbeda), sehingga perbaikan tidak berefek | Sedang | Test dengan payload berbentuk kiriman HP sungguhan (push lalu kirim ulang); titik dibandingkan sebagai angka, bukan teks |
| Fungsi tile rusak sehingga peta web kosong | Tinggi | Cast angka hanya bila bertipe number; test DB di CI; migrasi bisa dibalik |
| Kontrak berubah setelah sempat dipakai | Sedang | Belum ada yang ter-deploy atau dirilis; T2 dikerjakan sebelum deploy; mobile men-clamp saat membaca |
| `ProjectMapView.tsx` makin besar | Rendah | Logika di `mapColorMode.ts` dan `MapColorLegend.tsx`; file besar hanya wiring |
| Hijau/oranye default aplikasi mirip warna status verified/unverified | Sedang | Judul legenda selalu menyebut mode; pilihan mode terlihat di peta |
| Aturan tap berubah dari yang sudah dites | Rendah | Test untuk setiap kasus; uji di HP (Checkpoint B) |

## Pertanyaan terbuka (default dipakai bila tidak dijawab)
1. **T8 (Style di sheet Tracking Aktif).** Default: dikerjakan.
2. **Ukuran point di web mode Style** = `pointSize × ⅔`. Default: ya.
3. **Peta kecil di modal detail record** (`DataDetailMap`). Default: tetap memakai warna status.
4. **Pilihan warna diingat per browser**, bukan per akun. Default: ya.
5. **Test upgrade DB v6 → v7 di SQLite sungguhan** butuh dev dependency `sqflite_common_ffi`. Default: tidak (cek manual di HP).

## Baseline & perintah
- **terestria:** `flutter test` 714 lulus; `flutter analyze` 0 error, 29 warning.
- **gis-backend** (Git Bash). Unittest lokal: 64 lulus. Test `*_db` dan `tests_verification` hanya jalan di CI.
  ```
  PY="/c/Users/User/.conda/envs/django-env/python.exe"
  export PATH="/c/Users/User/.conda/envs/django-env/Library/bin:$PATH"
  "$PY" -m unittest mobile.tests_feature_style mobile.tests_photo_download mobile.tests_push_rules mobile.tests_pull_filter  # + modul test baru
  "$PY" manage.py check
  ```
- **gis-dashboard:** `npm test` 19 lulus; `npx tsc --noEmit` 1 error lama (`pages/api/auth/[...nextauth].tsx:13`); `next lint` dibandingkan per file dengan HEAD.
