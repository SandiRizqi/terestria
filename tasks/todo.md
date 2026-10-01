# TODO — Perbaikan hasil review + pilihan warna peta di web (1 Okt 2026)

Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md) · Plan sebelumnya: `plan-feature-style.md` (arsip lokal)
Repo: `gis-backend` @ `dev1` (T1–T3) · `terestria` @ `main` (T2, T4–T8) · `gis-dashboard` @ `dev1` (T9). Commit per task, tanpa push/deploy.
Baseline: `flutter test` 714, `flutter analyze` 0 error / 29 warning · backend unittest lokal 64 · dashboard `npm test` 19, `tsc` 1 error lama.

## Fase 1 — Backend (sebelum deploy `d54d508`)
- [x] T1 (kritis, gis-backend `ec74e6f`): verifikasi hanya di-reset bila isian form non-foto atau koordinat titik berubah; foto dan style tidak dicek; `updated_at` tetap naik. Test lokal +13 (`tests_verification_keep`), test DB +2 (CI).
- [ ] T2: kontrak style — `pointSize` 10–24, key asing diabaikan (backend `clean_style` + mobile `feature_style.dart` + `docs/sync-push-contract.md`).
- [ ] T3: tile MVT membawa 5 properti style (migrasi `0022`) + segmen versi `s2` di key cache tile.

### Checkpoint A
- [ ] Test lokal backend hijau, `manage.py check` bersih, migrasi konsisten (cek offline); test mobile T2 hijau.
- [ ] (User) CI: `tests_feature_style_db`, `tests_photo_download_db`, `tests_verification`, `tests_tile_style_db`.

## Fase 2 — Mobile
- [ ] T4: editor ukuran point — rentang per pemakai (Layers 4–20, feature 10–24), pratinjau = diameter marker di peta.
- [ ] T5: hit-test dua tingkat — yang kena langsung didahulukan; toleransi 24 dp hanya bila tidak ada yang kena langsung.
- [ ] T6: culling tampilan line/polygon pakai aturan bbox yang sama dengan hit-test (bbox dihitung saat data dimuat).
- [ ] T7: hapus kode mati `MarkerLayer` line/polygon di `_buildExistingDataLayers`.
- [ ] T8 (opsional): bagian Style di sheet stop & save "Tracking Aktif".

### Checkpoint B
- [ ] `flutter test` hijau; `flutter analyze` sesuai baseline.
- [ ] (User, di HP) blok bersebelahan, polygon bertumpuk, slider ukuran point + pratinjau, zoom di dalam blok besar, Style di Tracking Aktif.

## Fase 3 — Web dashboard
- [ ] T9: pilihan "Warna peta" (Status verifikasi / Style feature) + legenda mode aktif + diingat per browser; `sv=2` di URL tile.

### Checkpoint C
- [ ] Test lokal ketiga repo hijau; baseline analyze/tsc/lint tidak memburuk.
- [ ] (User) Uji manual T9 di browser setelah backend T3 ter-deploy di dev.
- [ ] (User) Deploy berurutan: backend (`d54d508` + T1–T3) → dashboard (T9) → rilis app.

## Dibawa dari build sebelumnya (style per feature + tap langsung)
- [ ] (User, di HP)
  - atur style saat koleksi dan saat edit, lalu lihat di peta project dan layar navigasi;
  - sync ke HP kedua;
  - upgrade DB v6 → v7 tanpa kehilangan data;
  - app versi lama tidak menghapus style;
  - edit dari dashboard tidak menghapus style;
  - ketepatan tap pada line tipis dan polygon kecil;
  - cluster di zoom rendah tetap zoom-in;
  - mode gambar dan alat ukur tetap menambah titik.
- Item build dashboard sebelumnya (download foto, polygon verifikasi) tetap di `gis-dashboard/tasks/todo.md`.
