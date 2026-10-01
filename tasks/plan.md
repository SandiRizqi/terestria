# Rencana: Form & Aturan Project — Tipe Field Baru, Builder Web Interaktif, Akurasi Minimum, Kombinasi Unik

Status: **disetujui user (2026-10-01)**; pertanyaan terbuka memakai default · Tanggal: 2026-10-01
Spec: [SPEC.md](../SPEC.md) (disetujui 2026-10-01).
Plan sebelumnya: `tasks/plan-style-review-fixes.md` (arsip lokal; versi git ada di riwayat `tasks/plan.md`). Item manual yang belum selesai dari plan itu dibawa ke `tasks/todo.md`.

Satu commit per task per repo, tanpa push/deploy. Status semua task dicatat di `tasks/todo.md` (terestria).

| Repo | Branch | Task |
|---|---|---|
| gis-backend | `dev1` | T1, T13–T15 |
| terestria | `main` | T2–T9, T16–T20 |
| gis-dashboard | `dev1` | T10–T12, T21–T25 |

## Ringkasan

Empat bagian dari SPEC, dikerjakan dalam empat fase. Tiap fase bisa dipakai sendiri:

1. **Tipe field (server + HP).** 5 tipe baru, min/maks + satuan, nilai default, dan perbaikan celah tipe.
2. **Tipe field (web).** Nilai tampil terformat; edit atribut dan popup peta memakai input sesuai tipe.
3. **Aturan project.** `min_accuracy` dan `unique_fields` di server dan HP.
4. **Builder project web.** Buat/edit project dari web dengan kartu field yang bisa diseret, dilipat, dan disalin; validasi langsung; pratinjau form; pengaturan aturan project.

## Keputusan arsitektur

1. **Satu sumber pengetahuan tipe per stack.**
   - HP: `fieldTypeFromName` + `field_type_info.dart` (nama, ikon) + `field_values.dart` (format/parse/validasi/tampilan).
   - Web: `fieldTypes.ts`.
   - Server: `validation.py`.
   - Aturan validasi diuji dengan tabel kasus yang sama di ketiganya.
2. **Tipe baru baru bisa dipilih di builder HP setelah inputnya ada.** T2 menambah tipe di model; T4–T6 menyalakannya satu per satu. Commit di antaranya tidak pernah menawarkan tipe tanpa input. Tipe baru yang datang dari server sebelum itu tampil sementara seperti teks.
3. **Pilihan ganda disimpan sebagai teks `"A; B"`,** urut sesuai opsi (SPEC Asumsi 2). Nama tipe yang tidak dikenal dipertahankan saat form disimpan ulang, di HP maupun web.
4. **Kombinasi unik di server memakai kolom terhitung `GeoData.unique_key`.**
   - Isinya kunci ternormalisasi (SPEC §3.7), dihitung saat record disimpan. Pencarian duplikat cukup satu query berindeks `(project, unique_key)`, tanpa memuat `form_data` semua record.
   - Saat `unique_fields` project berubah, kunci semua record project itu dihitung ulang (per batch).
   - Bila kunci baru sama dengan kunci tersimpan record itu, cek dilewati, jadi data duplikat lama tetap bisa diedit.
   - Cek + simpan berjalan dalam transaksi dengan `select_for_update` pada baris project.
5. **Aturan akurasi di server** memakai satu helper murni (point: akurasi titik; line/polygon: rata-rata titik GPS, akurasi > 0). Dipakai di `create`, `bulk_sync`, dan `partial_update` (hanya bila `points` dikirim). Penolakan memakai HTTP 422 + `error_code`.
6. **HP sudah menampilkan pesan server apa adanya bila ada `error_code`** (`SyncService._serverErrorMessage`). Penolakan `low_accuracy`/`duplicate` langsung terbaca, termasuk di versi app yang sekarang dipakai. Record tetap "belum sync" dengan pesan itu.
7. **Asal titik di HP** (SPEC §3.6):
   - tombol tambah titik dengan mode "ikuti GPS" → titik GPS (koordinat + akurasi fix);
   - crosshair digeser manual atau tap → manual, akurasi 0;
   - editor geometri: vertex sisipan = 0, vertex dipindah mempertahankan akurasinya.
   - Semua tampilan akurasi memperlakukan 0 sebagai "placed manually".
8. **Logika baru di file terpisah.** `data_collection_screen.dart` (±4.300 baris), `dynamic_form.dart` (±1.400), dan `MobileSurveyDashboard.tsx` (±1.250) hanya mendapat wiring. Logika ada di `project_rules.dart`, `field_values.dart`, `form_inputs/`, `fieldTypes.ts`, dan `builder/`.
9. **Builder web dibangun baru** di dialog project `MobileSurveyDashboard.tsx` (komponen di `builder/`). `CreateEditDialog.tsx` yang tidak terpasang dihapus. Project baru dari web mendapat id dari `crypto.randomUUID()`, karena endpoint project adalah upsert yang wajib `id`.
10. **Endpoint project sudah mengembalikan 400 untuk error validasi** (sebelumnya tertangkap jadi 500), lewat task keamanan "Batasi update project ke pembuatnya". Task itu juga menetapkan:
    - upsert dari non-pembuat → 200 `applied: false` tanpa perubahan;
    - PUT/PATCH dari non-pembuat → 403 `not_project_owner`;
    - `created_by` tidak bisa dipalsukan atau diganti.

## Grafik dependensi

```
Fase 1 — tipe field (server + HP)
  T1 BE validasi tipe/min-maks
  T2 HP model + daftar tipe ──► T3 HP helper nilai & validasi ──┬─► T4 teks panjang + skala
                                                               ├─► T5 pilihan ganda
                                                               ├─► T6 waktu & tanggal-waktu
                                                               ├─► T7 min/maks + satuan
                                                               └─► T9 filter/ekspor/detail
                                         T4–T7 ──► T8 nilai default
Fase 2 — tipe field (web)
  T10 fieldTypes.ts ──► T11 tampilan terformat ──► T12 input sesuai tipe (FieldValueInput)
Fase 3 — aturan project
  T13 BE pengaturan + migrasi 0023 ──┬─► T14 BE akurasi (422)
                                     └─► T15 BE unik (422)
  T16 HP model/DB v8/sync (◄ kontrak T13) ──┬─► T17 HP UI "Project rules"
                                            ├─► T18 HP akurasi: ambil titik & manual ──► T19 HP rata-rata & peringatan
                                            └─► T20 HP cek unik saat simpan (◄ T18: project_rules.dart)
Fase 4 — builder web
  T21 state & validasi builder (◄ T10) ──► T22 builder kartu + New project (◄ T12) ──┬─► T23 drag & drop
                                                                                    ├─► T24 pratinjau (◄ T12)
                                                                                    └─► T25 aturan project (◄ T13)
```

- T1, T10, dan T13 bisa dikerjakan paralel dengan fase sebelumnya. Urutan di bawah mengikuti fase.

## Tasks

### Fase 1 — Tipe field: server & HP

#### T1 — Backend: validasi tipe baru, `decimal`, min/maks (gis-backend)
**Deskripsi.** `validate_form_data` menerapkan SPEC §3.3:
- `time`, `datetime`, `multiselect` (bagian ⊆ opsi), `rating` (1–5; angka atau teks angka);
- `decimal` kini dicek sebagai angka;
- `min`/`max` untuk `number`/`decimal`;
- `textarea` tanpa cek.

Pesan error berbahasa Indonesia seperti pesan yang ada.

**Kriteria penerimaan**
- [ ] Setiap aturan §3.3 menolak contoh yang melanggar dan menerima contoh yang benar (tabel kasus, dipakai juga oleh test HP dan web).
- [ ] `min`/`max` inklusif, boleh salah satu saja, hanya untuk angka/desimal.
- [ ] Test lama tetap lulus (`tests_validation`, 13).

**Verifikasi:** `"$PY" -m unittest mobile.tests_field_types mobile.tests_validation`, lalu semua test lokal dan `manage.py check`.
**Dependensi:** tidak ada.
**File:** `mobile/validation.py`, `mobile/tests_field_types.py` (baru).
**Ukuran:** S.

#### T2 — HP: model field, daftar tipe tunggal, tipe tak dikenal dipertahankan (terestria)
**Deskripsi.**
- `FieldType` + `textarea`, `multiselect`, `time`, `datetime`, `rating`.
- `FormFieldModel` + `min`, `max`, `unit`. Nama tipe asli disimpan dan dikirim balik bila tipenya tidak dikenal.
- `field_type_info.dart` (baru): nama UI, ikon, deskripsi, dan tanda "bisa dipilih" per tipe. Menggantikan peta ikon/nama ganda di builder, `create_project_screen`, dan `project_detail_screen`.
- `cloud_project_dialog` dan `project_template_service` memakai `fieldTypeFromName` (perbaikan `decimal`).
- Payload sync project memuat `min`/`max`/`unit` dan nama tipe asli.
- Switch yang wajib menangani tipe baru diberi perilaku sementara seperti teks.

**Kriteria penerimaan**
- [ ] Round-trip JSON key baru. Tipe tak dikenal (mis. `signature`) berperilaku seperti teks, tetapi `toJson` tetap mengirim `signature`.
- [ ] `decimal` tetap `decimal` lewat cloud project dan template.
- [ ] Builder hanya menawarkan 7 tipe lama (nama + ikon dari daftar tipe). Layar detail project menampilkan nama dan ikon ke-12 tipe.
- [ ] Payload push project memuat `min`/`max`/`unit` bila diisi.

**Verifikasi:** `flutter test` (test model + daftar tipe baru, semua lama hijau); `flutter analyze` sesuai baseline.
**Dependensi:** tidak ada.
**File:**
- `lib/models/form_field_model.dart`, `lib/models/field_type_info.dart` (baru)
- `lib/widgets/form_field_builder.dart`, `lib/widgets/dynamic_form.dart`
- `lib/screens/project/create_project_screen.dart`, `project_detail_screen.dart`
- `lib/widgets/project/cloud_project_dialog.dart`, `lib/services/project_template_service.dart`, `lib/services/sync_service.dart`
- test

Banyak file, tetapi perubahannya kecil (dipaksa oleh penambahan enum).
**Ukuran:** M.

#### T3 — HP: helper nilai & aturan validasi bersama
**Deskripsi.** `lib/utils/field_values.dart` (baru, murni):
- pilihan ganda: gabung/pisah sesuai urutan opsi;
- waktu dan tanggal-waktu: format/parse;
- skala: parse;
- cek rentang angka;
- `displayValue(field, value)`: Yes/No, `4 / 5`, `35.5 cm`, `2026-10-01 07:15`.

`formFieldIssues` memakai aturan yang sama dengan server.

**Kriteria penerimaan**
- [ ] Tabel kasus T1 memberi hasil yang sama.
- [ ] Pesan jelas: "must be between 0 and 200 cm", "has an option that is not in the list", "is not a valid time", "must be 1–5".
- [ ] Test form lama tetap hijau.

**Verifikasi:** `flutter test test/utils/field_values_test.dart test/widgets/form_field_issues_test.dart`, lalu `flutter test` penuh dan `flutter analyze`.
**Dependensi:** T2.
**File:** `lib/utils/field_values.dart` (baru), `lib/widgets/dynamic_form.dart`, 2 file test (baru).
**Ukuran:** S–M.

#### T4 — HP: input teks panjang & skala 1–5
**Deskripsi.**
- `textarea`: teks beberapa baris; pin tetap ada; tanpa tombol QR dan tanpa toggle huruf.
- `rating`: 5 pilihan yang bisa diketuk; ketuk lagi untuk mengosongkan.
- Keduanya dinyalakan di builder.

**Kriteria penerimaan**
- [ ] `textarea` menyimpan string berbaris banyak; `required` bekerja.
- [ ] `rating` menyimpan bilangan bulat 1–5; dikosongkan → kosong; `required` bekerja.
- [ ] Builder menawarkan "Long text" dan "Rating (1–5)"; muat di 360 dp.

**Verifikasi:** test widget input + builder; `flutter test`; `flutter analyze`.
**Dependensi:** T3.
**File:** `lib/widgets/dynamic_form.dart`, `lib/widgets/form_inputs/rating_input.dart` (baru), `lib/models/field_type_info.dart`, test.
**Ukuran:** S–M.

#### T5 — HP: pilihan ganda
**Deskripsi.**
- Input daftar centang; menyimpan `"A; B"` sesuai urutan opsi.
- Editor opsi di builder dipakai bersama dropdown, dengan aturan: tanpa `;`, unik, tidak kosong.

**Kriteria penerimaan**
- [ ] Pilih B lalu A → tersimpan `"A; B"`; semua dilepas → kosong.
- [ ] Nilai lama berisi opsi yang sudah tidak ada tetap tampil (ditandai) dan ditolak validasi.
- [ ] Builder menolak opsi yang berisi `;` atau ganda.

**Verifikasi:** test widget input + builder; `flutter test`; `flutter analyze`.
**Dependensi:** T3.
**File:** `lib/widgets/form_inputs/multi_choice_input.dart` (baru), `lib/widgets/dynamic_form.dart`, `lib/widgets/form_field_builder.dart`, `lib/models/field_type_info.dart`, test.
**Ukuran:** M.

#### T6 — HP: waktu & tanggal-waktu
**Deskripsi.**
- Pemilih jam (24 jam) → `HH:mm`.
- Pemilih tanggal + jam → `YYYY-MM-DDTHH:mm:00.000`.
- Tombol "Now" dan tombol hapus.
- Keduanya dinyalakan di builder.

**Kriteria penerimaan**
- [ ] Format persis SPEC §3.1.
- [ ] Nilai tersimpan yang tidak valid (mis. dari app lama) ditandai validasi.
- [ ] Builder menawarkan "Time" dan "Date & time"; muat di 360 dp.

**Verifikasi:** test widget; `flutter test`; `flutter analyze`.
**Dependensi:** T3.
**File:** `lib/widgets/form_inputs/date_time_inputs.dart` (baru), `lib/widgets/dynamic_form.dart`, `lib/models/field_type_info.dart`, test.
**Ukuran:** M.

#### T7 — HP: batas min/maks & satuan
**Deskripsi.**
- Builder: isian min, maks, dan satuan untuk angka/desimal (min ≤ maks).
- Form: satuan tampil sebagai akhiran input. Nilai di luar batas memblokir simpan dengan pesan (lewat T3).

**Kriteria penerimaan**
- [ ] Builder menyimpan `min`/`max`/`unit` dan menolak min > maks.
- [ ] Form menampilkan akhiran "cm".
- [ ] 250 dengan maks 200 → diblokir; nilai di dalam batas → lolos.

**Verifikasi:** test widget builder + form; `flutter test`; `flutter analyze`.
**Dependensi:** T3.
**File:** `lib/widgets/form_field_builder.dart`, `lib/widgets/dynamic_form.dart`, test.
**Ukuran:** S.

#### T8 — HP: nilai default
**Deskripsi.**
- Builder: isian default per tipe, divalidasi dengan aturan field. Untuk tanggal/waktu/tanggal-waktu ada pilihan "Use the time the form opens" (`now`).
- Form: default diterapkan hanya untuk record baru (`DynamicForm` mendapat parameter `applyDefaults`), dengan prioritas draft → pin → default.
- "Save & next" menerapkan default lagi. Sheet Tracking Aktif menerapkannya; layar edit tidak.

**Kriteria penerimaan**
- [ ] SPEC §3.4 terpenuhi untuk semua tipe.
- [ ] Test prioritas draft → pin → default dan token `now`.
- [ ] Layar edit record tidak berubah.

**Verifikasi:** test widget/unit; `flutter test`; `flutter analyze`.
**Dependensi:** T4–T7 (input semua tipe sudah ada).
**File:** `lib/widgets/form_field_builder.dart`, `lib/widgets/dynamic_form.dart`, `lib/utils/field_values.dart`, `lib/screens/data_collection/data_collection_screen.dart`, `lib/widgets/tracking/attribute_form_sheet.dart`, test.
**Ukuran:** M.

#### T9 — HP: tipe baru di filter, ekspor, detail, lembar konflik
**Deskripsi.**
- Filter daftar data:
  - teks panjang, waktu, tanggal-waktu: berisi teks;
  - pilihan ganda: pilih satu opsi;
  - skala: 1–5.
- Ekspor GeoJSON/KML/SHP/CSV: nilai apa adanya.
- Dialog detail record, lembar konflik, dan judul record memakai `displayValue`.

**Kriteria penerimaan**
- [ ] Filter tiap tipe baru bekerja.
- [ ] Atribut tipe baru ikut di ekspor.
- [ ] Detail dan lembar konflik menampilkan nilai terformat.

**Verifikasi:** test ekspor + tampilan; `flutter test`; `flutter analyze`.
**Dependensi:** T3.
**File:** `lib/screens/project/project_detail_screen.dart`, `lib/services/export/geo_export.dart`, `lib/widgets/sync/conflict_sheet.dart`, `lib/screens/data_collection/data_collection_screen.dart` (dialog detail), `lib/utils/record_title.dart`, test.
**Ukuran:** M.

### Checkpoint A — tipe field di server & HP
- [ ] `flutter test` hijau, `flutter analyze` sesuai baseline; test lokal backend hijau.
- [ ] (User, di HP)
  - buat project dengan 5 tipe baru, min/maks/satuan, dan default; isi, simpan, sync;
  - pull di HP kedua;
  - field bertipe tak dikenal tidak berubah tipe saat project disimpan ulang.

### Fase 2 — Tipe field: web

#### T10 — Web: `fieldTypes.ts` (murni) + tipe data (gis-dashboard)
**Deskripsi.**
- Daftar 12 tipe (label, deskripsi).
- Parse, format, dan validasi dengan aturan SPEC §3.3; pilihan ganda gabung/pisah; resolusi default (termasuk `now`); `displayValue`.
- `types.ts`: union `FormField` 12 tipe + pengaturan (`options`, `min`, `max`, `unit`, `defaultValue`, `minPhotos`, `maxPhotos`); `Project` + `minAccuracy`, `uniqueFields` (opsional).

**Kriteria penerimaan**
- [ ] Test node memakai tabel kasus yang sama dengan T1/T3.
- [ ] Format tampilan sesuai SPEC.
- [ ] Tipe tak dikenal diperlakukan seperti teks.

**Verifikasi:** `npm test`; `npx tsc --noEmit` = baseline.
**Dependensi:** tidak ada (kontrak SPEC).
**File:** `components/mobilesurveyproject/fieldTypes.ts` (baru), `fieldTypes.test.mjs` (baru), `types.ts`.
**Ukuran:** S–M.

#### T11 — Web: tampilan nilai terformat
**Deskripsi.** Sel tabel data, `DataDetailModal`, dan popup peta menampilkan nilai lewat `displayValue` berdasarkan `formFields` project. Foto dikenali dari tipe field, dengan cadangan nilai berbentuk array untuk data lama.

**Kriteria penerimaan**
- [ ] Tampil: Yes/No, `4 / 5`, `35.5 cm`, `2026-10-01 07:15`; teks panjang mempertahankan baris baru.
- [ ] Data lama dan field yang tidak dikenal tampil seperti sekarang.

**Verifikasi:** `npm test`; `tsc`; lint per file dibanding HEAD; `next build`.
**Dependensi:** T10.
**File:** `ProjectDataTab.tsx`, `components/DataDetailModal.tsx`, `ProjectMapView.tsx` (tampilan popup), `ProjectDetailPanel.tsx` (meneruskan project bila perlu).
**Ukuran:** M.

#### T12 — Web: input sesuai tipe di Edit Attributes & popup peta
**Deskripsi.** `components/FieldValueInput.tsx` (baru) menyediakan input untuk semua tipe:
- min/maks/satuan, centang untuk pilihan ganda, boolean untuk checkbox;
- skala, `time`, `datetime-local`, `textarea`.

`EditFormModal` dan edit di popup peta memakainya, dengan validasi langsung dari `fieldTypes.ts`:
- key yang tidak ada di `formFields` tetap pakai input teks;
- foto tetap baca-saja (dikenali dari tipe).

**Kriteria penerimaan**
- [ ] Angka tersimpan sebagai angka, checkbox sebagai boolean, pilihan ganda sebagai `"A; B"`.
- [ ] Nilai tidak valid menampilkan pesan dan memblokir simpan.
- [ ] Edit field yang tidak disentuh tidak mengubah tipe nilainya.

**Verifikasi:** `npm test`; `tsc`; lint; `next build`.
**Dependensi:** T10, T11.
**File:** `components/FieldValueInput.tsx` (baru), `ProjectDataTab.tsx`, `ProjectMapView.tsx`.
**Ukuran:** M.

### Checkpoint B — tipe field di web
- [ ] `npm test`, `tsc` (baseline), lint, `next build` hijau.
- [ ] (User, di browser) Tampilan dan edit atribut tipe lama dan baru, di tabel maupun popup peta.

### Fase 3 — Aturan project

#### T13 — Backend: pengaturan project + migrasi `0023` (gis-backend)
**Deskripsi.**
- Field baru: `Project.min_accuracy` (float, null), `Project.unique_fields` (JSON list), dan `GeoData.unique_key` (Char, null, indeks `(project, unique_key)`). Migrasi `0023` ditulis manual dan dicek offline.
- `ProjectSerializer`:
  - mapping camelCase/snake_case, respons camelCase;
  - validasi rentang 0,01–500;
  - `unique_fields` ⊆ label yang memenuhi syarat, maksimal 5.
- Error validasi sudah dibalas 400 oleh `ProjectViewSet.create` (task keamanan); cukup pastikan pesan validasi baru ikut terkirim.

**Kriteria penerimaan**
- [ ] Round-trip pengaturan lewat API.
- [ ] Nilai tidak valid → 400 dengan pesan per field.
- [ ] Payload project lama (tanpa key baru) tidak berubah perilaku.
- [ ] Migrasi konsisten (cek offline).

**Verifikasi:** `"$PY" -m unittest mobile.tests_project_rules` + semua test lokal; `manage.py check`; cek migrasi offline; CI: `tests_project_rules_db`.
**Dependensi:** tidak ada.
**File:** `mobile/models.py`, `mobile/migrations/0023_project_rules.py`, `mobile/serializers.py`, `mobile/views.py`, `mobile/tests_project_rules.py` (baru), `mobile/tests_project_rules_db.py` (baru).
**Ukuran:** M.

#### T14 — Backend: aturan akurasi (422 `low_accuracy`)
**Deskripsi.**
- Helper murni `accuracy_violation(geometry_type, points, limit)`:
  - point: akurasi titik;
  - line/polygon: rata-rata titik dengan akurasi > 0; tanpa titik GPS → lolos.
- Diterapkan sebelum simpan di `create`, per item di `bulk_sync`, dan di `partial_update` hanya bila `points` dikirim.
- Respons sesuai SPEC §3.6, dicatat di sync log.

**Kriteria penerimaan**
- [ ] Point 7,4 m dengan batas 5 → 422; titik manual (0 atau null) → lolos.
- [ ] Rata-rata mengabaikan titik akurasi 0/null.
- [ ] `bulk_sync` menolak per item; `partial_update` tanpa `points` tidak dicek.
- [ ] Project tanpa batas tidak terpengaruh.

**Verifikasi:** test helper lokal + semua test lokal; `manage.py check`; CI: alur push nyata.
**Dependensi:** T13.
**File:** `mobile/validation.py`, `mobile/views.py`, `mobile/tests_project_rules.py`, `mobile/tests_project_rules_db.py`.
**Ukuran:** M.

#### T15 — Backend: aturan kombinasi unik (422 `duplicate`)
**Deskripsi.**
- Helper `unique_key(form_fields, unique_fields, form_data)` dengan normalisasi SPEC §3.7.
- `GeoData.unique_key` diisi saat simpan (serializer create/update) bila project punya aturan. Dihitung ulang per batch saat `unique_fields` project berubah.
- Cek di `create`, `bulk_sync`, dan `partial_update`, dalam transaksi dengan `select_for_update` project. Dilewati bila kunci sama dengan kunci tersimpan record itu.
- Respons sesuai SPEC §3.7, termasuk `existing_id`.

**Kriteria penerimaan**
- [ ] Normalisasi: `"a1 "`=`"A1"`, `10`=`10.0`=`"10"`, spasi berulang.
- [ ] Duplikat dari user lain ditolak; update record yang sama diterima.
- [ ] Duplikat lama tetap bisa diedit bila kuncinya tidak berubah; mengubah kunci menjadi kunci record lain → ditolak.
- [ ] Dua item berkunci sama dalam satu `bulk_sync` → item kedua ditolak.
- [ ] Kunci terisi ulang saat aturan project diubah.

**Verifikasi:** test lokal (helper + alur dengan mock) + semua test lokal; `manage.py check`; CI: alur DB.
**Dependensi:** T13.
**File:** `mobile/validation.py`, `mobile/serializers.py`, `mobile/views.py`, `mobile/tests_project_rules.py`, `mobile/tests_project_rules_db.py`.
**Ukuran:** M–L. Bagian paling berisiko; dikerjakan teliti dengan test per kasus.

#### T16 — HP: pengaturan project di model, DB v8, sync (terestria)
**Deskripsi.**
- `Project.minAccuracy` dan `uniqueFields` (JSON camelCase/snake_case).
- DB v8: kolom baru di `projects`, migrasi idempoten dengan pola `missingColumns`.
- Push project mengirim `min_accuracy`/`unique_fields`; pull membacanya.

**Kriteria penerimaan**
- [ ] Pemetaan baris v7 → v8 tanpa kehilangan data.
- [ ] Round-trip JSON.
- [ ] Payload push memuat pengaturan.

**Verifikasi:** `flutter test` (pola `db_v7_test.dart`); `flutter analyze`.
**Dependensi:** kontrak T13.
**File:** `lib/models/project_model.dart`, `lib/services/database_service.dart`, `lib/services/sync_service.dart`, test.
**Ukuran:** S–M.

#### T17 — HP: "Project rules" di pembuat project
**Deskripsi.** Bagian baru di `create_project_screen`:
- **Minimum accuracy (m):** opsional, 0,01–500.
- **Unique combination:** pilih field yang memenuhi syarat, berurutan, maksimal 5.
  - Field yang dipilih otomatis wajib diisi.
  - Mengganti label atau menghapus field ikut memperbarui kombinasi (berdasarkan id field).

**Kriteria penerimaan**
- [ ] Pengaturan tersimpan dan terkirim.
- [ ] Field kunci tidak bisa dibuat opsional.
- [ ] Rename/hapus field menjaga kombinasi tetap benar; muat di 360 dp.

**Verifikasi:** test widget; `flutter test`; `flutter analyze`.
**Dependensi:** T16.
**File:** `lib/screens/project/create_project_screen.dart`, `lib/widgets/project/project_rules_section.dart` (baru), `lib/models/field_type_info.dart` (syarat field kunci), test.
**Ukuran:** M.

#### T18 — HP: akurasi — ambil titik & titik manual
**Deskripsi.**
- `lib/services/project_rules.dart` (baru, murni): keputusan ambil titik, rata-rata akurasi GPS, kunci unik (dipakai T19/T20).
- Layar koleksi:
  - tombol tambah titik dengan mode ikuti GPS → titik GPS (koordinat + akurasi + metadata fix);
  - tanpa mode ikuti → manual (`accuracy: 0`); tap di mode gambar → 0.
- Project point: ambil titik GPS dengan akurasi > batas, atau tanpa fix, ditolak dengan peringatan. Simpan record point yang titiknya > batas juga diblokir.
- Banner GPS menampilkan batas project.
- Editor geometri: vertex sisipan = 0; vertex dipindah mempertahankan akurasinya.
- Semua tampilan akurasi memperlakukan 0 sebagai "placed manually".

**Kriteria penerimaan**
- [ ] Logika keputusan ambil titik teruji untuk semua kombinasi: ikut/tidak ikut, ada/tidak fix, di bawah/di atas batas, project tanpa batas.
- [ ] Perilaku editor geometri teruji.
- [ ] Project tanpa batas: alur ambil titik sama seperti sekarang, kecuali akurasi kini ikut tersimpan.

**Verifikasi:** test unit `project_rules` + `GeometryEditSession`; `flutter test`; `flutter analyze`.
**Dependensi:** T16.
**File:** `lib/services/project_rules.dart` (baru), `lib/screens/data_collection/data_collection_screen.dart`, `lib/services/geometry_edit.dart`, `lib/screens/project/geometry_editor_screen.dart` (label manual), test.
**Ukuran:** M.

#### T19 — HP: akurasi — rata-rata line/polygon & peringatan
**Deskripsi.**
- Widget ringkasan akurasi: rata-rata dibanding batas, dengan peringatan bila melebihi. Tampil di form "Survey data", sheet Tracking Aktif, dan layar edit. Simpan tetap boleh.
- Editor geometri menandai vertex di atas batas dan menampilkan rata-rata langsung.

**Kriteria penerimaan**
- [ ] Teks seperti "Average GPS accuracy 8.4 m — project limit 5 m". Tanpa titik GPS → tidak ada peringatan.
- [ ] Menghapus vertex buruk langsung memperbarui rata-rata.
- [ ] Muat di 360 dp.

**Verifikasi:** test widget; `flutter test`; `flutter analyze`.
**Dependensi:** T18.
**File:** `lib/widgets/collection/accuracy_summary.dart` (baru), `lib/screens/data_collection/data_collection_screen.dart`, `lib/widgets/tracking/attribute_form_sheet.dart`, `lib/screens/project/edit_geo_data_screen.dart`, `lib/screens/project/geometry_editor_screen.dart`, test.
**Ukuran:** M.

#### T20 — HP: cek kombinasi unik saat simpan
**Deskripsi.**
- `project_rules.uniqueKey` memakai normalisasi yang sama dengan server.
- Cari duplikat di record lokal project.
- Blokir simpan di form koleksi (record baru), sheet Tracking Aktif, dan layar edit (hanya bila kunci berubah). Pesannya sama dengan server.

**Kriteria penerimaan**
- [ ] `"a1 "` dan `"A1"` terdeteksi duplikat; `10` dan `10.0` juga.
- [ ] Edit tanpa mengubah kunci tetap boleh.
- [ ] Pesan menyebut nilai-nilai field kunci.

**Verifikasi:** test unit + widget; `flutter test`; `flutter analyze`.
**Dependensi:** T16, T18.
**File:** `lib/services/project_rules.dart`, `lib/screens/data_collection/data_collection_screen.dart`, `lib/widgets/tracking/attribute_form_sheet.dart`, `lib/screens/project/edit_geo_data_screen.dart`, test.
**Ukuran:** M.

### Checkpoint C — aturan project
- [ ] Semua test lokal hijau (HP + backend); migrasi `0023` konsisten.
- [ ] (User) CI: `tests_project_rules_db` dan test DB lain.
- [ ] (User, di HP, backend dev sudah memuat T13–T15)
  - ambil point dengan akurasi buruk → ditolak;
  - tracking dengan rata-rata buruk → peringatan → push ditolak → hapus titik buruk → sync berhasil;
  - duplikat lokal diblokir, duplikat dari HP lain ditolak server.

### Fase 4 — Builder project web interaktif

#### T21 — Web: state & validasi builder (murni) (gis-dashboard)
**Deskripsi.**
- `builder/builderState.ts`: tambah, salin, hapus, pindah, dan ubah field. Kombinasi unik dijaga berdasarkan id field (rename/hapus ikut).
- `builder/builderValidation.ts`:
  - **error:** label kosong/ganda, aturan opsi, min > maks, panjang satuan, default tidak valid, aturan kombinasi unik, rentang akurasi;
  - **peringatan:** rename, ganti tipe, atau hapus field pada project yang sudah punya data.

**Kriteria penerimaan**
- [ ] Test node untuk semua aturan dan operasi state.

**Verifikasi:** `npm test`; `tsc`.
**Dependensi:** T10.
**File:** `builder/builderState.ts` (baru), `builder/builderValidation.ts` (baru), 2 test (baru).
**Ukuran:** S–M.

#### T22 — Web: builder kartu field di dialog project + "New project"
**Deskripsi.**
- `builder/ProjectBuilder.tsx` + `FieldCard.tsx` menggantikan daftar field baca-saja di dialog project `MobileSurveyDashboard.tsx`. Kartu bisa dilipat, disalin, dan dihapus; pengaturan sesuai tipe; error dan peringatan langsung tampil di kartu.
- Tombol "New project": id dari `crypto.randomUUID()`; tipe geometri hanya bisa dipilih saat membuat.
- Payload menyimpan urutan field.
- `CreateEditDialog.tsx` dan ekspornya di `index.ts` dihapus.

**Kriteria penerimaan**
- [ ] Buat project baru dan edit form project yang ada berhasil (cek manual ke backend dev).
- [ ] Error memblokir simpan; peringatan tidak.
- [ ] Respons `applied: false` dari server (user bukan pembuat) tampil sebagai gagal, bukan "saved".
- [ ] `tsc`, lint, dan `next build` hijau.

**Verifikasi:** `npm test`; `tsc`; lint; `next build`; manual browser.
**Dependensi:** T21, T12 (input default memakai `FieldValueInput`).
**File:** `builder/ProjectBuilder.tsx` (baru), `builder/FieldCard.tsx` (baru), `MobileSurveyDashboard.tsx`, `CreateEditDialog.tsx` (hapus), `index.ts`.
**Ukuran:** M–L.

#### T23 — Web: drag & drop urutan
**Deskripsi.**
- `framer-motion` `Reorder.Group`/`Reorder.Item` dengan pegangan drag (`useDragControls`), supaya isian di kartu tetap bisa diklik dan diketik.
- Tombol naik/turun untuk keyboard, dengan `aria-label`.

**Kriteria penerimaan**
- [ ] Seret dan tombol mengubah urutan; urutan tersimpan.
- [ ] Bisa dipakai dengan keyboard.
- [ ] Tidak ada dependency baru.

**Verifikasi:** `npm test` (operasi pindah di T21); `tsc`; lint; `next build`; manual.
**Dependensi:** T22.
**File:** `builder/ProjectBuilder.tsx`, `builder/FieldCard.tsx`.
**Ukuran:** S–M.

#### T24 — Web: pratinjau form langsung
**Deskripsi.**
- `builder/FormPreview.tsx`: panel bergaya layar HP yang menampilkan field berurutan memakai `FieldValueInput`, dengan state lokal yang interaktif.
- Menampilkan tanda wajib, satuan, default (termasuk `now`), dan pesan validasi.
- Layar lebar: panel di samping. Layar sempit: tab "Preview".

**Kriteria penerimaan**
- [ ] Perubahan di builder langsung terlihat.
- [ ] Mengisi pratinjau tidak mengubah project.

**Verifikasi:** `tsc`; lint; `next build`; manual.
**Dependensi:** T22, T12.
**File:** `builder/FormPreview.tsx` (baru), `builder/ProjectBuilder.tsx`, `MobileSurveyDashboard.tsx` (tata letak).
**Ukuran:** M.

#### T25 — Web: aturan project di builder
**Deskripsi.**
- `builder/ProjectRulesSection.tsx`: isian akurasi minimum dan pemilih kombinasi unik (chip berurutan dari field yang memenuhi syarat, maksimal 5). Field yang dipilih otomatis wajib.
- Payload dan muat edit memakai `minAccuracy`/`uniqueFields`.
- Pesan 400 dari server tampil.

**Kriteria penerimaan**
- [ ] Pengaturan tersimpan dan termuat ulang.
- [ ] Field yang dipilih jadi wajib; menghapus field mengeluarkannya dari kombinasi.
- [ ] Error validasi tampil di builder.

**Verifikasi:** `npm test`; `tsc`; lint; `next build`; manual dengan backend dev (T13).
**Dependensi:** T22, T13.
**File:** `builder/ProjectRulesSection.tsx` (baru), `builder/ProjectBuilder.tsx`, `MobileSurveyDashboard.tsx`, `types.ts`.
**Ukuran:** M.

### Checkpoint D — selesai
- [ ] Ketiga repo: semua test lokal hijau; baseline analyze/`tsc`/lint tidak memburuk; `next build` berhasil.
- [ ] (User) CI test DB backend lulus.
- [ ] (User) Uji manual Checkpoint A–C dan builder web: buat project baru, seret urutan, pratinjau, aturan project, simpan, lalu pull di HP.
- [ ] Urutan deploy di bawah dijalankan.

## Urutan deploy (oleh user)
1. gis-backend `dev1`: T1, T13–T15 (migrasi `0023`) → CI hijau → deploy.
2. Rilis app (T2–T9, T16–T20) dan deploy dashboard (T10–T12, T21–T25), setelah backend.
3. Pembuat project memakai app versi baru sebelum memakai tipe baru (SPEC §3.8).

## Risiko
| Risiko | Dampak | Mitigasi |
|---|---|---|
| Aturan unik salah menolak data sah (normalisasi beda HP vs server) | Tinggi | Tabel kasus normalisasi yang sama di test HP dan server; update tanpa ganti kunci tidak dicek |
| Push bersamaan lolos sebagai duplikat | Tinggi | Transaksi + `select_for_update` project; kunci terindeks |
| Hitung ulang `unique_key` lambat pada project besar | Sedang | Per batch; hanya saat aturan berubah |
| Aturan akurasi menolak data project yang sekarang aktif | Sedang | Hanya berlaku bila `min_accuracy` diisi; titik manual/null lolos; pesan menjelaskan cara memperbaiki |
| Arti akurasi 0 (manual) tertukar dengan "sangat akurat" | Sedang | Semua tampilan menulis "placed manually"; rata-rata hanya dari titik akurasi > 0 |
| File besar makin besar | Sedang | Logika di file baru (`project_rules`, `field_values`, `form_inputs/`, `builder/`); file besar hanya wiring |
| Aturan validasi HP/web/server tidak sama | Sedang | Satu tabel kasus diuji di ketiga stack |
| App lama menurunkan tipe baru menjadi `text` | Sedang | Didokumentasikan (SPEC §3.8); versi baru mempertahankan nama tipe tak dikenal |

## Pertanyaan terbuka (default dipakai bila tidak dijawab)
1. **Hapus `CreateEditDialog.tsx`** (builder lama yang tidak terpasang). Default: dihapus di T22.
2. **Batas lebar layar untuk pratinjau di samping.** Default: ≥ 1100 px; di bawahnya jadi tab.
3. **Pesan di HP saat rata-rata akurasi melebihi batas** — peringatan di form (bukan dialog). Default: ya.

## Baseline & perintah
- **terestria:** `flutter test` 735 lulus; `flutter analyze` 0 error, 29 warning.
- **gis-backend** (Git Bash):
  ```
  PY="/c/Users/User/.conda/envs/django-env/python.exe"
  export PATH="/c/Users/User/.conda/envs/django-env/Library/bin:$PATH"
  "$PY" -m unittest mobile.tests_feature_style mobile.tests_photo_download mobile.tests_push_rules \
    mobile.tests_pull_filter mobile.tests_verification_keep mobile.tests_tile_style mobile.tests_validation  # + modul baru
  "$PY" manage.py check
  ```
  Baseline: 99 lulus. Test `*_db` hanya jalan di CI.
- **gis-dashboard:** `npm test` 29 lulus; `npx tsc --noEmit` 1 error lama; `next lint` dibanding per file dengan HEAD; `next build`.
