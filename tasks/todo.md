# TODO — Form & Aturan Project (1 Okt 2026)

Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md) · Plan sebelumnya: `plan-style-review-fixes.md` (arsip lokal)
Repo: `gis-backend` @ `dev1` (T1, T13–T15) · `terestria` @ `main` (T2–T9, T16–T20) · `gis-dashboard` @ `dev1` (T10–T12, T21–T25). Commit per task, tanpa push/deploy.
Baseline: `flutter test` 735, `flutter analyze` 0 error / 29 warning · backend unittest lokal 99 · dashboard `npm test` 29, `tsc` 1 error lama.

## Fase 1 — Tipe field: server & HP
- [x] T1 (gis-backend `06742d2`): validasi `time`, `datetime`, `multiselect`, `rating`, `decimal`, min/maks. Test lokal +7 (`tests_field_types`, tabel kasus bersama).
- [x] T2: model field (5 tipe baru, min/max/unit, nama tipe asli dipertahankan), daftar tipe tunggal (`field_type_info.dart`), perbaikan `decimal` (cloud/template), payload sync (`toSyncJson`). Builder kini juga mempertahankan `defaultValue` saat field diedit.
- [x] T3: `field_values.dart` (parse/format/validasi/tampilan per tipe) + `formFieldIssues` memakai `fieldValueIssue` — tabel kasus sama dengan server.
- [x] T4: input teks panjang (banyak baris, tanpa QR/toggle huruf) & skala 1–5 (`RatingInput`, ketuk lagi = kosong) + builder; dropdown tipe di builder `isExpanded` (label panjang tidak meluber di 360 dp).
- [x] T5: input pilihan ganda `"A; B"` (`MultiChoiceInput`; nilai lama di luar daftar tetap tampil & ditandai) + editor opsi bersama dropdown: minimal 1, unik (huruf besar/kecil diabaikan; dropdown dengan opsi ganda dulu bisa crash), tanpa `;` untuk pilihan ganda. Opsi kini disimpan tanpa spasi di tepi.
- [x] T6: input waktu (`HH:mm`, pemilih 24 jam) & tanggal-waktu (`YYYY-MM-DDTHH:mm:00.000`; pilih tanggal lalu jam) dengan "Now" dan hapus; nilai lama tak valid tampil apa adanya dan ditandai validasi. Semua tipe kini punya input, jadi penanda `pickable` dihapus.
- [x] T7: builder — isian Min/Max/Unit untuk angka/desimal (boleh salah satu, menolak min > maks, satuan ≤ 10 huruf, dibuang bila tipe diganti); form — satuan sebagai akhiran yang selalu terlihat, nilai di luar batas ditandai inline ("Value must be between 0 and 200 cm") dan simpan diblokir lewat `formFieldIssues`.
- [x] T8: nilai default — `resolveDefaultValue`/`defaultValueIssue`/`normalizeDefaultValue` (murni); `DynamicForm(applyDefaults)` hanya mengisi field yang belum ada di data (draft & isian yang sengaja dikosongkan tidak ditimpa, pin tetap menang), dipakai form koleksi (juga setelah "Save & next") dan sheet Tracking Aktif, tidak di layar edit; builder: `DefaultValueEditor` per tipe (teks/angka/tanggal/jam dengan "saat form dibuka", dropdown/centang/skala lewat daftar, pilihan ganda lewat centang) divalidasi terhadap opsi & batas, dibuang bila tipe diganti. Perbaikan kecil: teks progres field wajib tidak meluber.
- [x] T9: filter daftar data per tipe lewat `fieldFilterKind`/`fieldFilterMatches` (murni, di `field_values.dart`): teks panjang, waktu, tanggal-waktu, dan angka = berisi teks (nilai tersimpan atau tampilannya, mis. "2026-10-01 07:15"); pilihan ganda = pilih satu opsi (record yang memuat opsi itu); skala = chip 1–5. Chip filter jadi `FilterOptionChips` (dipakai dropdown, pilihan ganda, skala). Ekspor GeoJSON/CSV sudah membawa nilai apa adanya, kini dikunci test (app hanya punya ekspor GeoJSON/CSV; KML/SHP hanya impor layer). Dialog detail (detail project & layar koleksi), baris pratinjau di daftar data, judul record, dan lembar konflik memakai `displayFieldValue` lewat `recordValueText`; konflik tidak lagi melaporkan beda bentuk simpan (4 / "4", 36 / 36.0). Perbaikan kecil: filter tanggal dulu tidak pernah cocok (nilai tersimpan berakhiran `T00:00:00.000`); judul record tanpa field non-foto tidak lagi menampilkan isi daftar foto; isian kosong tidak lagi tampil/cocok sebagai "null".

### Checkpoint A
- [x] Test lokal HP + backend hijau; analyze sesuai baseline (2 Okt: HP 857 test, analyze 0 error / 29 warning; backend 121 OK, `manage.py check` bersih).
- [ ] (User, di HP) project dengan tipe baru: isi, simpan, sync, pull di HP kedua; tipe tak dikenal tidak berubah.

## Fase 2 — Tipe field: web
- [x] T10 (gis-dashboard `ef02e41`): `fieldTypes.ts` (murni) — 12 tipe + label, parse/format angka/jam/tanggal-jam, pilihan ganda, validasi dengan pesan sama dengan HP, default (`now`), `displayValue`; tipe tak dikenal = teks. `types.ts`: 12 tipe + pengaturan field, `Project.minAccuracy`/`uniqueFields`. `npm test` 29 → 69 (tabel kasus bersama server/HP), `tsc` baseline.
- [x] T11 (gis-dashboard `2dabde1`): tabel (ringkasan & baris terbuka), `DataDetailModal`, popup peta, dan pratinjau pencarian peta menampilkan nilai lewat definisi field (`entryText`): Yes/No, `4 / 5`, `35.5 cm`, `2026-10-01 07:15`, `"A; B"`; teks panjang mempertahankan baris baru. Foto dikenali dari tipe (`isPhotoEntry`); kunci tanpa definisi tetap seperti dulu (daftar = foto). Isian kosong tidak lagi tampil "null".
- [x] T12 (gis-dashboard `2fe06d0`): `components/FieldValueInput.tsx` (`FieldValueInput` + `AttributeFields`) dipakai Edit Attributes di tabel & popup peta: angka (+satuan, koma/titik → number), teks panjang, date/time/datetime-local (format app), dropdown, centang pilihan ganda (`"A; B"`), checkbox (boolean), bintang 1–5; foto baca-saja; kunci tanpa definisi = input teks. Urutan field form (juga yang belum ada di record), lalu kunci lain. Masalah isian (`formIssues`, pesan sama dengan HP) memblokir simpan; foto tidak dicek. Nilai yang tidak disentuh tidak berubah. `npm test` 75.

### Checkpoint B
- [x] `npm test`, `tsc` (baseline), lint, `next build` hijau (2 Okt: 75 test; `tsc` 1 error lama; lint per file sama dengan HEAD; build berhasil).
- [ ] (User, di browser) tampilan & edit atribut tipe lama dan baru.

## Fase 3 — Aturan project
- [x] T13 (gis-backend `8a6c096`): `Project.min_accuracy` (0,01–500 m, null = tanpa aturan), `Project.unique_fields` (≤ 5 label, bukan foto/teks panjang), `GeoData.unique_key` = SHA-256 kunci ternormalisasi (panjang tetap, aman untuk indeks) + indeks parsial `(project, unique_key)`; migrasi `0023` manual, cek offline: tidak ada migrasi tertunda. Serializer: camelCase/snake_case, respons camelCase, 400 dengan pesan per field; `unique_fields` hanya dicek bila dikirim (app lama yang mengubah form tidak ditolak, aturan tersimpan dibiarkan). Test lokal +15 (`tests_project_rules`), CI: `tests_project_rules_db`.
- [x] T14 (gis-backend `d2a6e22`): `accuracy_violation`/`accuracy_rejection` (murni): point = akurasi titik, line/polygon = rata-rata titik GPS (akurasi > 0), batas inklusif, tanpa titik GPS → lolos. 422 `low_accuracy` + `details` di `create` (setelah cek nonaktif & konflik, tercatat di sync log), per item di `bulk_sync`, dan `partial_update` hanya bila `points` dikirim. Test lokal +11, CI: `tests_project_rules_db` (+4).
- [x] T15 (gis-backend `c8eaa51`): normalisasi kunci (murni, `validation.py`) — teks/dropdown/tanggal/jam/lainnya: trim, spasi berulang jadi satu, tanpa beda huruf besar/kecil; angka/desimal/skala sebagai angka (`10`=`10.0`=`"10"`, format `_fmt_number`); checkbox true/false; dicek hanya bila semua field kunci terisi. `GeoData.unique_key` diisi saat simpan; dihitung ulang per batch (`rules.refresh_unique_keys`) bila aturan atau tipe field kunci berubah. 422 `duplicate` + `details.fields/existing_id` di `create`, per item `bulk_sync`, `partial_update` (bila form dikirim); kunci tidak berubah → tidak dicek (duplikat lama tetap bisa diedit). Cek + simpan dalam transaksi dengan `select_for_update` baris project; aturan dibaca dari baris yang dikunci. Test lokal +14 (161 total), CI: `tests_project_rules_db` (+5). **HP (T20) wajib memakai normalisasi yang sama.**
- [x] T16: `Project.minAccuracy` (angka positif, selain itu null) / `uniqueFields` (rusak → []) dengan JSON camelCase/snake_case, `copyWith(clearMinAccuracy)`; DB v8 (`projects.minAccuracy REAL`, `uniqueFields TEXT DEFAULT '[]'`, migrasi idempoten `missingColumns`; `projectToRow`/`projectFromRow` statis & teruji); push `SyncService.projectPayload` mengirim `min_accuracy`/`unique_fields`, pull (`parseProjectFromServer`, `fromServerJson`) membacanya; project dari cloud lewat `CloudProject.toProject()` membawa aturan; layar edit project mempertahankan aturan (UI di T17).
- [x] T17: `ProjectRulesSection` (akurasi minimum 0,01–500 m opsional; kombinasi unik ≤ 5 field `canBeUniqueKey` = bukan foto/teks panjang, dipilih lewat menu, chip hapus) di pembuat & edit project; field kunci dilacak lewat id (ganti nama ikut, hapus/ganti tipe keluar), disimpan sebagai label; field kunci otomatis wajib (`withRequiredKeyFields`) dan builder field mengunci "Required" (`lockRequired`); kartu field menandai "Unique key". Perbaikan kecil: badge "Cannot be changed" di judul Geometry Type tidak meluber di 360 dp.
- [x] T18: `lib/services/project_rules.dart` (murni): `decidePointCapture` (mode ikuti + fix segar ≤ 30 dtk → titik GPS dengan akurasi; project point berbatas: fix di atas batas / tanpa fix / akurasi tak diketahui → ditolak "Accuracy 7.4 m — this project needs 5 m or better."; tanpa mode ikuti → manual akurasi 0), `accuracyViolation`/`averageGpsAccuracy` (rumus sama dengan server), pesan & `projectLimitText`. Layar koleksi: tombol tambah titik & tap mode gambar memakai aturan itu, simpan record point di atas batas diblokir, kartu status GPS menampilkan "Project limit 5 m" (merah bila GPS sekarang tidak cukup). Editor geometri: vertex sisipan = 0, vertex dipindah mempertahankan akurasi; `GeoPoint.isManual` (0 / tanpa akurasi) → "placed manually".
- [x] T19: `accuracySummary`/`isAboveLimit` (murni) + widget `AccuracySummary` ("Average GPS accuracy 8.4 m — project limit 5 m"; melebihi batas → peringatan "server will reject…", simpan tetap boleh; tanpa titik GPS / tanpa batas → tidak tampil) di form "Survey data", sheet Tracking Aktif, dan layar edit. Editor geometri: parameter `minAccuracy`, vertex di atas batas merah, rata-rata langsung di toolbar (hapus vertex buruk langsung memperbarui).
- [ ] T20: cek kombinasi unik saat simpan (koleksi, sheet, edit).

### Checkpoint C
- [ ] Test lokal hijau; migrasi `0023` konsisten (cek offline).
- [ ] (User) CI: `tests_project_rules_db` dan test DB lain.
- [ ] (User, di HP) point akurasi buruk ditolak; tracking rata-rata buruk → push ditolak → hapus titik → sync berhasil; duplikat lokal diblokir, duplikat dari HP lain ditolak server.

## Fase 4 — Builder project web
- [ ] T21: `builderState.ts` + `builderValidation.ts` (murni, teruji).
- [ ] T22: builder kartu field di dialog project + "New project" + hapus `CreateEditDialog.tsx`.
- [ ] T23: drag & drop urutan (`framer-motion` Reorder) + tombol naik/turun.
- [ ] T24: pratinjau form langsung.
- [ ] T25: aturan project di builder (akurasi minimum, kombinasi unik).

### Checkpoint D
- [ ] Ketiga repo: test lokal hijau; baseline tidak memburuk; `next build` berhasil.
- [ ] (User) CI test DB backend; uji manual builder web (buat project, seret, pratinjau, aturan, simpan, pull di HP).
- [ ] (User) Deploy: backend (`0023`) → app & dashboard.

## Dibawa dari build sebelumnya (perbaikan review style + warna peta web)
- [ ] (User) CI: `tests_feature_style_db`, `tests_verification`, `tests_tile_style_db`, `tests_photo_download_db`.
- [ ] (User) Deploy berurutan: backend (`d54d508`, `ec74e6f`, `c4873f4`, `cbe6e21`; migrasi `0021`, `0022`) → dashboard (`6fb96e8`) → rilis app.
- [ ] (User, di HP)
  - blok bersebelahan langsung terbuka saat diketuk;
  - polygon bertumpuk memunculkan daftar pilihan;
  - slider ukuran point dan pratinjaunya;
  - zoom di dalam blok besar;
  - Style di sheet Tracking Aktif;
  - daftar uji style per feature sebelumnya (sync ke HP kedua, upgrade DB v6 → v7, app lama, edit dashboard, ketepatan tap).
- [ ] (User, di browser) pilihan "Warna peta" (Status/Style) setelah backend `cbe6e21` ter-deploy.
- Celah keamanan "update project tanpa cek pembuat" sudah dikerjakan terpisah dari plan ini (task "Batasi update project ke pembuatnya", 1 Okt 2026). Butuh test DB di CI (`tests_project_owner_db`) dan deploy backend.
