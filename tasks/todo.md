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
- [ ] T11: tampilan nilai terformat (tabel, detail, popup).
- [ ] T12: `FieldValueInput` di Edit Attributes & popup peta.

### Checkpoint B
- [ ] `npm test`, `tsc` (baseline), lint, `next build` hijau.
- [ ] (User, di browser) tampilan & edit atribut tipe lama dan baru.

## Fase 3 — Aturan project
- [ ] T13 (backend): `min_accuracy`, `unique_fields`, `GeoData.unique_key`, migrasi `0023`, serializer, 400 untuk error validasi.
- [ ] T14 (backend): aturan akurasi → 422 `low_accuracy`.
- [ ] T15 (backend): aturan kombinasi unik → 422 `duplicate` (transaksi + kunci project).
- [ ] T16: `Project.minAccuracy`/`uniqueFields`, DB v8, push/pull.
- [ ] T17: bagian "Project rules" di pembuat project HP.
- [ ] T18: akurasi — titik GPS (mode ikuti) vs manual (0), tolak titik point di luar batas, editor geometri.
- [ ] T19: akurasi — rata-rata line/polygon & peringatan (form, sheet, edit, editor).
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
