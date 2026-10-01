# SPEC — Form & Aturan Project: Tipe Field Baru, Builder Web Interaktif, Akurasi Minimum, Kombinasi Unik

> Status: **disetujui user (2026-10-01)**; diperinci saat menyusun plan (builder web, cara ambil titik GPS) · Tanggal: 2026-10-01
> Repo: **terestria** (Flutter, package `geoform_app`) + **gis-backend** (Django, app `mobile`) + **gis-dashboard** (Next.js 13, `components/mobilesurveyproject`).
> Spec sebelumnya (Style per Feature + Tap Langsung, beserta revisi 2026-10-01) diarsip di `tasks/spec-feature-style.md`.

## 1. Objective

**Siapa:**
- pembuat project, di HP atau web dashboard;
- surveyor yang mengisi data di HP;
- pemeriksa yang melihat dan mengoreksi data di web.

**Masalah sekarang:**
1. Hanya ada 7 tipe field: teks satu baris, angka, desimal, tanggal, dropdown (pilih satu), checkbox, dan foto. Belum ada pilihan lebih dari satu jawaban, catatan panjang, jam, atau penilaian.
2. Angka tidak punya batas, jadi salah ketik (mis. diameter 1500 cm) tetap tersimpan. `defaultValue` ada di model, tetapi tidak bisa diatur dan tidak dipakai form.
3. Web dashboard belum punya builder project:
   - dialog project (`MobileSurveyDashboard.tsx`) hanya bisa mengubah nama, deskripsi, dan collector;
   - daftar field hanya pratinjau baca-saja;
   - project baru tidak bisa dibuat dari web;
   - builder lama `CreateEditDialog.tsx` (tanpa urutan, tanpa `decimal`/`checkbox`) tidak terpasang di mana pun.
4. Akurasi GPS hanya diatur global per HP (Settings, 5–200 m). Project yang butuh data presisi tidak bisa menuntut batas sendiri.
5. Tidak ada pencegahan data ganda, mis. TPH yang sama tercatat dua kali.
6. Celah yang ditemukan saat survei kode:
   - field `decimal` berubah menjadi `text` saat project diambil dari cloud (`cloud_project_dialog.dart`) atau dari template (`project_template_service.dart`);
   - "Edit Attributes" dan popup peta di web mengedit semua isian sebagai teks, sehingga angka dan centang tersimpan ulang sebagai string;
   - app yang tidak mengenal sebuah tipe membacanya sebagai `text`; bila form project disimpan ulang dari app itu, tipe aslinya hilang.

**Yang dibangun:**
- **A. Tipe field & aturan isian.**
  - 5 tipe baru: teks panjang, pilihan ganda, waktu, tanggal & waktu, skala 1–5.
  - Batas min/maks + satuan untuk angka dan desimal.
  - Nilai default.
  - Didukung penuh di HP, server, dan web.
- **B. Builder project web interaktif.**
  - Project baru bisa dibuat dari web, dan form project yang ada bisa diedit.
  - Kartu field bisa diseret untuk mengurutkan, dibuka-tutup, dan disalin.
  - Kesalahan langsung tampil.
  - Ada pratinjau form seperti di HP.
- **C. Akurasi minimum per project** (`min_accuracy`).
- **D. Kombinasi unik per project** (`unique_fields`), mis. WERKS + BLOCK_NAME + NO_TPH.
- **Perbaikan celah** di poin 6.

### Keputusan user (2026-10-01)
| Aspek | Keputusan |
|---|---|
| Tipe baru | Pilihan ganda, teks panjang, waktu & tanggal-waktu, skala 1–5. Tanpa tipe lanjutan (tanda tangan, beberapa field foto, teks petunjuk). |
| Aturan isian | Min/maks + satuan (angka/desimal) dan nilai default. |
| Web dashboard | Didukung penuh: builder menawarkan semua tipe, dan edit atribut memakai input sesuai tipe. |
| Builder web | Drag & drop urutan, pratinjau form langsung, kartu lipat + duplikat, validasi langsung. |
| Akurasi — project point | Titik GPS di luar batas ditolak saat diambil, dengan peringatan. Server juga menolak push. |
| Akurasi — tracking line/polygon | Dinilai dari rata-rata akurasi setelah tracking selesai. Boleh disimpan di HP dengan peringatan; server menolak push sampai titik yang buruk dihapus dan rata-ratanya memenuhi batas. |
| Titik gambar manual | Akurasi disimpan 0, jadi otomatis lolos. |
| Kombinasi unik | Abaikan huruf besar/kecil dan spasi. HP menolak simpan bila record lokal dengan kombinasi sama sudah ada; server menolak push duplikat. |

### Asumsi (koreksi sebelum disetujui)
1. **Satu spec, dikerjakan bertahap:** A → C/D → B. Tiap fase bisa dipakai sendiri.
2. **Pilihan ganda disimpan sebagai teks** `"A; B"` (urut sesuai daftar opsi), bukan array.
   - Alasannya: banyak bagian web menganggap array = foto, dan app versi lama tetap bisa menampilkan teks.
   - Konsekuensinya: opsi pilihan ganda tidak boleh mengandung `;`.
3. **Skala tetap 1–5**, tidak bisa diatur.
4. **Nilai default hanya untuk record baru.** Urutan prioritas: draft → nilai yang di-pin → default → kosong. Tanggal, waktu, dan tanggal-waktu punya pilihan "saat form dibuka".
5. **Min/maks hanya untuk angka dan desimal**, tidak untuk tanggal. Satuan hanya untuk tampilan: nilainya tidak berubah, dan nama kolom ekspor tidak ikut berubah.
6. **Rata-rata akurasi line/polygon hanya dari titik GPS** (akurasi > 0). Titik manual (akurasi 0) tidak ikut dirata-rata, supaya menambah titik manual tidak bisa "menurunkan" rata-rata. Feature yang seluruhnya manual otomatis lolos.
7. **Memindah vertex di editor geometri tetap menyimpan akurasi asalnya;** vertex baru yang ditambahkan manual = 0. Rata-rata hanya bisa diperbaiki dengan menghapus titik yang buruk atau mengambil ulang.
8. **Batas project tidak mengubah Settings HP.** Pipeline GPS global (`maxAccuracyMeters`) tetap seperti sekarang. Batas project dicek saat titik dimasukkan ke project dan saat simpan/push.
9. **Kombinasi unik berlaku per project.**
   - Record terhapus diabaikan, dan record itu sendiri tidak dihitung.
   - Field yang masuk kombinasi unik otomatis wajib diisi.
   - Semua tipe boleh dipakai kecuali foto dan teks panjang.
10. **Data lama yang sudah duplikat** saat aturan dipasang dibiarkan. Record lama tetap bisa diedit selama kombinasinya tidak diubah. Yang ditolak: record baru, atau perubahan yang membuat kombinasinya sama dengan record lain.
11. **Aturan akurasi dan unik berlaku untuk semua penulisan ke server:** push dari HP, `bulk_sync`, dan edit dari web. Pengecualian:
    - edit web yang tidak mengubah titik tidak dicek akurasinya;
    - edit yang tidak mengubah field kunci tidak dicek uniknya.
12. **Pratinjau form di web** meniru tampilan dan perilaku dasar form HP, bukan render yang identik per piksel. Pratinjau memakai komponen input yang sama dengan edit atribut di web.
13. **Tanpa dependency baru.** Drag & drop memakai `framer-motion` yang sudah terpasang; app memakai widget Flutter bawaan.
14. **Builder web untuk project yang sudah punya data:**
    - tipe geometri tidak bisa diubah, seperti sekarang;
    - mengganti label, mengganti tipe, atau menghapus field memunculkan peringatan di kartu, karena nilai di record lama tidak ikut dipindahkan;
    - peringatan ini tidak memblokir simpan.

## 2. Tech Stack
- **Mobile:** Flutter `^3.5.1`, `sqflite` (DB lokal v7 → v8), `flutter_map ^7.0.2`. Tanpa dependency baru.
- **Backend:** Django 4.2 + DRF, PostgreSQL, Python 3.9 (conda `django-env`).
- **Web:** Next.js 13 + React + MapLibre, TypeScript 4.9, `framer-motion ^10` (komponen `Reorder` untuk drag & drop). Test helper murni dengan `node --test`.

## 3. Kontrak Data

### 3.1 Tipe field & format nilai di `form_data`
| `type` | Nama di UI | Nilai tersimpan | Status |
|---|---|---|---|
| `text` | Text | string satu baris | ada (scan QR, pin, huruf besar/kecil) |
| `textarea` | Long text | string, boleh berisi baris baru | **baru** |
| `number` | Number | angka | ada |
| `decimal` | Decimal | angka | ada |
| `date` | Date | string `YYYY-MM-DDT00:00:00.000` (ISO lokal) | ada |
| `time` | Time | string `HH:mm` (24 jam) | **baru** |
| `datetime` | Date & time | string `YYYY-MM-DDTHH:mm:00.000` (ISO lokal, sama dengan format tanggal) | **baru** |
| `dropdown` | Dropdown | string (satu opsi) | ada |
| `multiselect` | Multiple choice | string: opsi terpilih digabung `"; "` sesuai urutan opsi, mis. `"Ulat api; Tikus"` | **baru** |
| `checkbox` | Checkbox | boolean | ada |
| `rating` | Rating (1–5) | bilangan bulat 1–5 | **baru** |
| `photo` | Photo | daftar objek foto | ada; tetap satu field per form |

### 3.2 Definisi field (`form_fields`)
Key baru bersifat opsional; app dan web versi lama mengabaikannya.
```json
{ "id": "f-dia", "label": "Diameter", "type": "decimal", "required": true,
  "min": 0, "max": 200, "unit": "cm", "defaultValue": null }
{ "id": "f-hama", "label": "Jenis hama", "type": "multiselect", "required": false,
  "options": ["Ulat api", "Kumbang tanduk", "Tikus"] }
```
- `min`, `max`: angka, inklusif, boleh salah satu saja. `unit`: teks ≤ 10 karakter. Ketiganya hanya untuk `number`/`decimal`.
- `options`: untuk `dropdown` dan `multiselect`; minimal 1, unik, tidak kosong. Opsi `multiselect` tidak boleh mengandung `;`.
- `defaultValue`: string, lihat §3.4.
- **Tipe tak dikenal** dibaca seperti `text`, tetapi nama tipe aslinya dipertahankan saat form disimpan ulang (HP dan web).
- Di HP, nama tipe hanya dibaca lewat satu fungsi (`fieldTypeFromName`), termasuk saat mengambil project dari cloud dan dari template.

### 3.3 Validasi isian
- **HP** memblokir simpan bila ada isian yang melanggar, seperti sekarang.
- **Server** tetap **lenient**: record diterima dan ditandai INVALID dengan `validation_errors`, mengikuti perilaku `validate_form_data` sekarang.
- Aturannya sama di kedua sisi:

| Tipe | Aturan |
|---|---|
| semua | `required` → tidak kosong. `multiselect` minimal 1 opsi; `checkbox` harus dicentang (aturan lama). |
| `number`, `decimal` | Angka valid, dan dalam `min`/`max` bila diatur. Server kini juga memeriksa `decimal`. |
| `time` | `HH:mm` atau `HH:mm:ss`, jam 00–23, menit 00–59. |
| `datetime` | Tanggal dan jam ISO yang valid. |
| `multiselect` | Setiap bagian ada di `options`. |
| `rating` | Bilangan bulat 1–5, berupa angka atau teks angka (mis. dari app lama). |
| `dropdown`, `date` | Aturan lama. |
| `text`, `textarea` | Tanpa cek tipe. |

### 3.4 Nilai default
| Tipe | `defaultValue` |
|---|---|
| `text`, `textarea` | teks apa adanya |
| `number`, `decimal` | angka (harus dalam min/maks) |
| `date`, `time`, `datetime` | nilai tetap dengan format §3.1, atau `now` = saat form dibuka |
| `dropdown` | salah satu opsi |
| `multiselect` | opsi digabung `"; "` |
| `checkbox` | `true` / `false` |
| `rating` | `1`–`5` |
| `photo` | tidak ada |

Default diterapkan hanya saat form record **baru** dibuka (termasuk setelah "Save & next"), dan hanya bila field masih kosong. Prioritas: draft → nilai yang di-pin → default.

### 3.5 Pengaturan project
| Server (`Project`) | Mobile / JSON respons | Isi |
|---|---|---|
| `min_accuracy` (float, null) | `minAccuracy` | Batas akurasi GPS dalam meter; null = tanpa aturan. Rentang 0,01–500. |
| `unique_fields` (list JSON, default `[]`) | `uniqueFields` | Label field yang membentuk kombinasi unik, berurutan; kosong = tanpa aturan. Maksimal 5 field. |

- **Backend:** migrasi `0023`. `ProjectSerializer` menerima snake_case dan camelCase, dan mengirim camelCase (seperti `formFields`). Validasi:
  - `unique_fields` harus label field yang ada, bukan foto dan bukan teks panjang;
  - `min_accuracy` dalam rentang.
- **Mobile:** DB v8 menambah kolom `minAccuracy REAL` dan `uniqueFields TEXT DEFAULT '[]'` di tabel `projects`. Keduanya ikut push/pull project.
- **Builder** (HP dan web) menjaga `unique_fields` tetap konsisten: field kunci yang diganti labelnya ikut diperbarui, dan field kunci yang dihapus keluar dari kombinasi.

### 3.6 Aturan akurasi (`min_accuracy`)
- Akurasi tiap titik diambil dari `accuracy` (meter) di `points`.
- **Asal titik di layar koleksi.** Tombol tambah titik sekarang menaruh titik di crosshair tanpa akurasi. Aturannya menjadi:
  - mode **ikuti GPS** aktif → titik diambil dari fix GPS saat itu (koordinat + akurasi + metadata fix), lalu dicek terhadap batas project;
  - crosshair digeser manual, atau tap di mode gambar → **titik manual**, disimpan dengan `accuracy: 0`;
  - titik tracking membawa akurasi dari GPS, seperti sekarang.
- Vertex baru yang disisipkan di editor geometri juga manual (`accuracy: 0`). Vertex yang dipindah mempertahankan akurasi asalnya (Asumsi 7).
- Titik tanpa nilai akurasi (data lama, edit dari web) diperlakukan seperti titik manual.

| Geometri | Yang dinilai | HP | Server |
|---|---|---|---|
| Point | Akurasi titik | Ambil titik GPS dengan akurasi > batas **ditolak** dengan peringatan, mis. "Accuracy 7.4 m — this project needs 5 m or better". Simpan record point yang titiknya > batas juga diblokir. | Push ditolak |
| Line / polygon | Rata-rata akurasi titik GPS (akurasi > 0); tanpa titik GPS → lolos | Tracking dan tambah titik tidak ditolak. Form simpan, sheet Tracking Aktif, dan layar edit menampilkan rata-rata dibanding batas; bila melebihi, muncul **peringatan** tetapi tetap boleh disimpan. Editor geometri menandai vertex yang akurasinya di atas batas. | Push ditolak bila rata-rata > batas |

- **Penolakan server:** HTTP **422**, record tidak disimpan:
  ```json
  {"success": false, "error_code": "low_accuracy",
   "message": "Average GPS accuracy 8.4 m is above this project's limit (5 m). Remove the inaccurate points and sync again.",
   "details": {"limit": 5, "value": 8.4, "measure": "average"}}
  ```
  Untuk point, `"measure": "point"`.
- **Di HP:** record tetap "belum sync" dengan pesan itu. Setelah titik buruk dihapus, sync berikutnya diterima.
- **`bulk_sync`:** item yang ditolak masuk `errors[]` dengan `error_code` yang sama; item lain tetap diproses.
- **Edit dari web** yang tidak mengubah `points` tidak dicek akurasinya.

### 3.7 Aturan kombinasi unik (`unique_fields`)
- **Kunci** = nilai field-field `unique_fields` setelah dinormalisasi:
  - teks, dropdown, tanggal, waktu: spasi di tepi dibuang, spasi berulang jadi satu, tidak peka huruf besar/kecil;
  - angka, desimal, skala: dibandingkan sebagai angka (`10`, `10.0`, dan `"10"` sama);
  - `checkbox`: true/false.
- Dicek hanya bila semua field kunci terisi.
- **Server** mengecek sebelum menyimpan: pada create/upsert dan `bulk_sync`, serta pada edit dari web yang mengubah field kunci.
  - Dicari record lain di project yang sama (tidak terhapus, `mobile_id` berbeda) dengan kunci yang sama.
  - Bila ada, push ditolak dengan HTTP **422**:
    ```json
    {"success": false, "error_code": "duplicate",
     "message": "WERKS=A1, BLOCK_NAME=B07, NO_TPH=12 already exists in this project.",
     "details": {"fields": {"WERKS": "A1", "BLOCK_NAME": "B07", "NO_TPH": "12"}, "existing_id": "..."}}
    ```
  - Update yang tidak mengubah kunci tidak dicek, jadi data duplikat lama tetap bisa diedit.
  - Aman dari push bersamaan: bila project punya aturan unik, cek dan simpan berjalan dalam satu transaksi dengan mengunci baris project (`select_for_update`).
- **HP:**
  - Saat simpan record baru, atau edit yang mengubah field kunci, simpan diblokir bila ada record lokal lain di project dengan kunci yang sama. Pesannya sama dengan pesan server.
  - Penolakan server (`duplicate`) tampil sebagai pesan error record, dan record tetap belum sync.

### 3.8 Kompatibilitas
| Situasi | Perilaku |
|---|---|
| App lama + tipe baru | Field tampil sebagai teks; isian divalidasi server (lenient, INVALID bila salah). Edit form project dari app lama mengubah tipe baru menjadi `text`, jadi **app pembuat project perlu diperbarui sebelum memakai tipe baru**. |
| App lama + `min_accuracy` / `unique_fields` | App lama tidak mengecek, tetapi server tetap menolak push (`low_accuracy` / `duplicate`). Pesan server tampil sebagai error sync. |
| App baru + backend lama | Tipe baru tidak divalidasi server, dan pengaturan project baru diabaikan (tidak ada penolakan). Urutan deploy: backend dulu. |
| Web lama + data baru | Nilai pilihan ganda, waktu, dan skala tampil sebagai teks atau angka biasa. |
| Data yang sudah ada | Tidak diubah. Aturan baru hanya berlaku untuk penulisan berikutnya. |

## 4. Commands

**Mobile** (`D:\Developments\terestria`):
```
flutter test                # baseline: 735 lulus
flutter analyze             # baseline: 0 error, 29 warning — tidak boleh bertambah
```

**Backend** (`D:\Developments\gis-backend`, Git Bash):
```
PY="/c/Users/User/.conda/envs/django-env/python.exe"
export PATH="/c/Users/User/.conda/envs/django-env/Library/bin:$PATH"
"$PY" -m unittest mobile.tests_feature_style mobile.tests_photo_download mobile.tests_push_rules \
  mobile.tests_pull_filter mobile.tests_verification_keep mobile.tests_tile_style \
  mobile.tests_validation   # baseline: 99 lulus (+ modul test baru)
"$PY" manage.py check
```
- Test yang butuh DB (`*_db.py`, `tests_verification`) hanya jalan di CI, karena DB test lokal dilarang.
- Migrasi ditulis manual, lalu dicek offline (autodetector, tanpa DB).

**Web** (`D:\Developments\gis-dashboard`):
```
npm test                    # baseline: 29 lulus (node --test)
npx tsc --noEmit            # baseline: 1 error lama (pages/api/auth/[...nextauth].tsx:13)
npx next lint --file <file> # dibandingkan per file dengan HEAD
npx next build
```

## 5. Project Structure (file baru / disentuh)

**Mobile**
| File | Isi |
|---|---|
| `lib/models/form_field_model.dart` | 5 tipe baru, `min`/`max`/`unit`, nama tipe asli dipertahankan |
| `lib/models/field_type_info.dart` | **baru**: nama UI, ikon, dan deskripsi per tipe (satu sumber untuk builder dan layar project) |
| `lib/utils/field_values.dart` | **baru**, murni: format/parse nilai per tipe, default (`now`), aturan validasi bersama, teks tampilan nilai |
| `lib/widgets/dynamic_form.dart` + `lib/widgets/form_inputs/` | Input tipe baru. Input baru ditaruh di folder terpisah karena `dynamic_form.dart` sudah ±1.400 baris. |
| `lib/widgets/form_field_builder.dart` | Pemilihan tipe baru, opsi, min/maks/satuan, default |
| `lib/screens/project/create_project_screen.dart` | Bagian "Project rules" (akurasi minimum, kombinasi unik) dan ikon tipe |
| `lib/models/project_model.dart`, `lib/services/database_service.dart` | `minAccuracy`, `uniqueFields`, DB v8 |
| `lib/services/project_rules.dart` | **baru**, murni: rata-rata akurasi, cek titik, kunci unik ternormalisasi |
| `lib/services/sync_service.dart` | Payload project (pengaturan baru + key field baru) dan pesan `low_accuracy` / `duplicate` |
| `lib/screens/data_collection/data_collection_screen.dart` | Tolak titik GPS (point), titik manual = 0, cek akurasi dan unik saat simpan, info batas di banner GPS |
| `lib/screens/project/edit_geo_data_screen.dart`, `geometry_editor_screen.dart` | Rata-rata dibanding batas, tandai vertex buruk, cek unik |
| `lib/widgets/tracking/attribute_form_sheet.dart` | Peringatan akurasi dan cek unik di stop & save |
| `lib/screens/project/project_detail_screen.dart` | Filter dan tampilan tipe baru |
| `lib/services/export/geo_export.dart`, `lib/widgets/sync/conflict_sheet.dart`, `lib/utils/record_title.dart` | Tipe baru di ekspor, lembar konflik, dan judul record |
| `lib/widgets/project/cloud_project_dialog.dart`, `lib/services/project_template_service.dart` | Memakai `fieldTypeFromName` (perbaikan `decimal`) |

**Backend**
| File | Isi |
|---|---|
| `mobile/validation.py` | Aturan tipe baru, min/maks, `decimal`; helper akurasi dan kunci unik |
| `mobile/models.py`, `mobile/migrations/0023_project_rules.py` | `min_accuracy`, `unique_fields` |
| `mobile/serializers.py` | `ProjectSerializer`: pengaturan baru + validasi |
| `mobile/views.py` | `create`, `bulk_sync`, `partial_update`: penolakan 422 (`low_accuracy` / `duplicate`), transaksi + kunci project |
| `mobile/tests_field_types.py`, `mobile/tests_project_rules.py` | Test lokal (mock) |
| `mobile/tests_project_rules_db.py` | Test DB (CI) |

**Web**
| File | Isi |
|---|---|
| `components/mobilesurveyproject/types.ts` | `FormField` (12 tipe + pengaturan), `Project` (`minAccuracy`, `uniqueFields`) |
| `components/mobilesurveyproject/fieldTypes.ts` (+ `.test.mjs`) | **baru**, murni: daftar tipe & label, format/parse/validasi nilai, default, kunci unik |
| `components/mobilesurveyproject/components/FieldValueInput.tsx` | **baru**: input per tipe, dipakai edit atribut, popup peta, dan pratinjau |
| `components/mobilesurveyproject/builder/` | **baru**: `ProjectBuilder.tsx` (daftar kartu + Reorder), `FieldCard.tsx` (kartu lipat, pegangan drag, duplikat), `FormPreview.tsx`, `ProjectRulesSection.tsx`, `builderValidation.ts` (+ test) |
| `components/mobilesurveyproject/MobileSurveyDashboard.tsx` | Tombol "New project" (UUID dibuat di browser), dialog project memakai builder baru, payload menyertakan pengaturan baru |
| `components/mobilesurveyproject/CreateEditDialog.tsx`, `index.ts` | Builder lama yang tidak terpasang — dihapus, termasuk ekspornya |
| `ProjectDataTab.tsx`, `ProjectMapView.tsx`, `components/DataDetailModal.tsx` | Edit atribut dan popup memakai input sesuai tipe; tampilan nilai terformat |

Semua file `*.md` di terestria di-gitignore, jadi dokumen ini di-commit dengan `git add -f`.

## 6. Code Style
- Ikuti pola yang ada:
  - model immutable dengan `copyWith`/`toJson`/`fromJson`;
  - logika murni dipisah dari widget/komponen agar bisa diuji.
- Komentar dan nama test dalam bahasa Indonesia.
- Teks UI di HP dalam bahasa Inggris. Teks UI di web mengikuti komponen sekitarnya (form dan modal dalam bahasa Inggris).
- Backend mengikuti pola `mobile/tests_push_rules.py`: ORM di-mock untuk test lokal, test DB di CI.
- Satu tempat untuk tiap pengetahuan tipe:
  - **HP:** `fieldTypeFromName` + `field_type_info.dart` + `field_values.dart`;
  - **web:** `fieldTypes.ts`;
  - **server:** `validation.py`.

## 7. Testing Strategy
TDD: test merah dulu, satu commit per task.
- **Unit (Dart):**
  - `field_values` per tipe: format, parse, validasi, default `now`;
  - `formFieldIssues` untuk tipe baru dan min/maks;
  - `project_rules`: rata-rata tanpa titik manual, cek titik point, normalisasi kunci unik;
  - JSON `FormFieldModel` (key baru, tipe tak dikenal dipertahankan);
  - JSON `Project` dan pemetaan DB v8.
- **Widget (Dart, lebar 360 dp):**
  - builder dialog untuk tipe dan pengaturan baru;
  - input `textarea`, `multiselect`, `time`, `datetime`, `rating`, dan satuan;
  - default terisi hanya di record baru;
  - peringatan akurasi;
  - pesan duplikat yang memblokir simpan.
- **Backend:**
  - lokal (mock): aturan validasi, helper akurasi dan kunci unik, `ProjectSerializer`;
  - CI (DB): penolakan 422 `low_accuracy` / `duplicate` di push dan `bulk_sync` (per item), update tanpa mengubah kunci tetap diterima, edit web.
- **Web (`node --test`):** `fieldTypes.ts` dan `builderValidation.ts`. Komponen dicek dengan `tsc`, lint, dan `next build`.
- **Manual:**
  - di HP: ambil point dengan akurasi buruk, tracking dengan rata-rata buruk → hapus titik → sync, duplikat;
  - di browser: drag & drop, pratinjau, edit atribut per tipe.

## 8. Boundaries
- **Always**
  - TDD per task; `flutter analyze`, `tsc`, dan lint tidak boleh memburuk.
  - Kompatibel dua arah: app lama ↔ backend baru, app baru ↔ backend lama.
  - Validasi isian di server tetap lenient (INVALID, bukan ditolak).
  - Hanya aturan akurasi dan unik yang menolak penulisan.
- **Ask first**
  - Menambah dependency.
  - Mengubah format simpan tipe yang sudah ada.
  - Menjalankan validasi ulang (backfill) pada data produksi.
  - Mengubah kode/status error yang sudah ada (403 `project_inactive`, 409 `conflict`).
- **Never**
  - Menyentuh `lib/config/api_config.dart`, perubahan lokal `pubspec.yaml`, atau git stash "temporary api_config changes".
  - Men-stage `*.pyc`.
  - Push atau deploy tanpa diminta.
  - Mengubah atau menghapus nilai record yang sudah ada.
  - Menolak push karena aturan isian field.

## 9. Success Criteria
1. Builder di HP dan web menawarkan 12 tipe dengan nama yang jelas, dan pengaturan yang sesuai tipe: opsi, min/maks/satuan, default, jumlah foto. Tipe yang tidak dikenal dipertahankan saat disimpan ulang.
2. Form di HP menampilkan 5 tipe baru dan menyimpan nilainya sesuai §3.1; satuan tampil di input angka.
3. Aturan §3.3 identik di HP (memblokir simpan) dan server (INVALID); server kini juga memeriksa `decimal`.
4. Default §3.4 hanya terisi di record baru, dengan prioritas draft → pin → default.
5. Project dengan `min_accuracy`:
   - **point:** ambil titik GPS di luar batas ditolak dengan peringatan; server menolak push (422 `low_accuracy`);
   - **line/polygon:** form dan layar edit menampilkan rata-rata dibanding batas, dengan peringatan; push ditolak sampai rata-rata ≤ batas, lalu diterima setelah titik buruk dihapus;
   - titik manual (akurasi 0) lolos.
6. Project dengan `unique_fields`:
   - HP memblokir simpan duplikat lokal (tidak peka huruf besar/kecil dan spasi);
   - server menolak push duplikat (422 `duplicate`), termasuk dari user lain dan push bersamaan;
   - edit record lama yang tidak mengubah kunci tetap diterima.
7. Edit atribut dan popup peta di web memakai input sesuai tipe: angka tetap angka, checkbox tetap boolean, pilihan ganda lewat centang. Foto tetap tidak bisa diedit di sana.
8. Web menampilkan nilai terformat: Yes/No, `4 / 5`, `35.5 cm`, tanggal-waktu ringkas, dan baris baru di teks panjang.
9. Builder web:
   - project baru bisa dibuat dari web, dan form project yang ada bisa diedit;
   - drag & drop dan tombol naik/turun mengubah urutan field, dan urutannya tersimpan;
   - kartu field bisa dilipat dan disalin;
   - kesalahan tampil langsung di kartu;
   - pratinjau form ikut berubah langsung;
   - akurasi minimum dan kombinasi unik bisa diatur.
10. Di HP, filter daftar data, ekspor (GeoJSON/KML/SHP/CSV), tampilan detail, dan lembar konflik menangani tipe baru.
11. Celah §1.6 tertutup: `decimal` tetap `decimal` lewat cloud dan template, dan tipe tak dikenal tidak hilang saat disimpan ulang.
12. Semua test lokal hijau:
    - `flutter analyze` tanpa warning baru;
    - `tsc` tanpa error baru, lint tanpa masalah baru, `next build` berhasil;
    - test DB backend lulus di CI.

## 10. Open Questions (tidak menghalangi; default dipakai bila tidak dijawab)
1. **Pemisah pilihan ganda** `"; "`. Default: ya.
2. **Maksimal field dalam kombinasi unik.** Default: 5.
3. **Rentang `min_accuracy`.** Default: 0,01–500 m.
4. **Rata-rata akurasi ditampilkan di detail record web?** Default: tidak, di tahap ini.
5. **Validasi ulang data lama dengan aturan baru** (perintah backfill)? Default: tidak dijalankan otomatis; user yang memutuskan.
