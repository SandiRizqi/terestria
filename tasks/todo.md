# TODO — Halaman Project: list, pilih & hapus, layout baru, edit koordinat alat ukur (8 Okt 2026)

Plan: [plan.md](plan.md) · Plan sebelumnya: `plan-form-rules.md` / `todo-form-rules.md` (arsip lokal)
Repo: `terestria` @ `main`. Commit per task, tanpa push/deploy. Jangan sentuh `lib/config/api_config.dart`, perubahan lokal `pubspec.yaml`, dan stash "temporary api_config changes".
Baseline (8 Okt): `flutter test` 913 lulus · `flutter analyze` 0 error / 29 warning (2 Okt).

## Fase 1 — Data project: list, pilih, hapus
- [x] T1: Tampilan list + tombol grid/list.
  - `GeoDataListTile` (`lib/widgets/project/`): ikon geometri, judul `recordTitle`, ringkasan, titik status (hijau tersinkron / kuning belum di-upload / merah gagal + alasan), menu ⋮ Edit/Delete hanya bila boleh.
  - Ringkasan dari `lib/utils/record_summary.dart` (murni): isian kedua (terformat, ≤ 30 karakter), luas polygon/panjang line dengan unit Settings, dan "you"/nama pengumpul + waktu singkat (jam hari ini, "yesterday", tanggal).
  - `DataViewToggle` di ujung kanan baris filter; pilihan disimpan lewat `DataViewModeStore` (SharedPreferences, berlaku untuk semua project). Grid tetap bawaan dan tidak berubah.
  - Teks "N of M records" pindah ke baris sendiri di bawah tombol filter, supaya tidak terpotong di 360 dp.
  - Test 913 → 935; analyze 0 error / 29 warning (sama dengan baseline).
- [x] T2: Mode pilih + pilih semua.
  - Masuk mode pilih: tekan lama record (langsung tercentang) atau menu ⋮ "Select Records".
  - `SelectionAppBar` menggantikan AppBar: "N selected", Select all / Deselect all (hanya record yang terlihat), dan ✕ untuk batal. Back = keluar dari mode pilih. FAB disembunyikan selama mode pilih.
  - List: checkbox menggantikan ikon geometri, latar hijau tipis bila terpilih, menu ⋮ disembunyikan. Grid: checkbox di pojok kiri atas, garis hijau bila terpilih, tombol edit/hapus disembunyikan. Ketuk = centang/lepas (bukan buka detail).
  - `RecordSelection` (murni): toggle, pilih/lepas semua yang terlihat, `retain` — dipanggil di `_applyFilters`, jadi record yang tersembunyi filter/cari atau terhapus otomatis lepas dari pilihan.
  - Test 935 → 948; analyze 0 error / 29 warning. Perilaku di level layar (tekan lama, Back, FAB) belum ada test-nya (layar butuh DB & service) → dicek di HP pada Checkpoint A.
- [x] T3: Hapus terpilih + kosongkan data lokal — **hanya dari HP** (keputusan user 9 Okt). Semua record terpilih boleh dihapus, termasuk kiriman pengumpul lain (sudah di server, bisa di-Pull lagi).
  - Bar pilihan: tombol 🗑 "Delete from this phone". Dialog menyebut berapa yang sudah di server (tetap di server) dan berapa yang belum di-upload (hilang permanen, saran sync dulu), plus "Nothing is deleted on the server."
  - Menu ⋮ "Clear Local Data": bawaan hanya record yang sudah di server. Record belum di-upload ikut hanya bila "Also delete N not uploaded yet" dicentang. Tombol "Delete N" mengikuti jumlah, dan nonaktif bila 0.
  - `DatabaseService.deleteGeoDataBatch`: satu transaksi; `deleteGeoDataRows` (dapat diuji) menghapus record + konflik sync per potongan 500 id (batas parameter SQLite).
  - Hapus diblokir selama sync berjalan ("Wait until the sync finishes."). Hapus satuan (tombol di tile) tidak berubah.
  - Test 948 → 960; analyze 0 error / 29 warning. Catatan: test DB sungguhan (sqflite ffi) tidak dibuat, karena butuh dev dependency baru di `pubspec.yaml` yang sedang berisi perubahan lokal. Diganti test dengan executor tiruan.

### Checkpoint A
- [ ] Test hijau; analyze tidak memburuk.
- [ ] (User, di HP) list/grid, pilih, hapus terpilih, kosongkan data lokal.

## Fase 2 — Layout seperti template (palet `AppTheme` tetap)
- [x] T4: Layout detail project seperti template 08.
  - AppBar terang (warna latar app) berisi indikator koneksi, Export, dan menu ⋮ (isi menu tetap). Cari di AppBar diganti kotak cari di halaman.
  - Header di halaman, ikut tergulir bersama data (`CustomScrollView`; grid/list jadi sliver, pull-to-refresh di seluruh halaman):
    - nama project besar + "Created by … · updated 2 h ago" (`relativeTime`, murni);
    - kartu Type | Records | Fields;
    - progres sync, banner "N records not synced" (foto tertunda + petunjuk offline/project belum di server, tombol Sync gelap `textPrimary`, nonaktif saat offline/sync), banner konflik;
    - kotak cari + tombol filter hijau berlencana jumlah filter;
    - baris "N records" / "N of M records" + Clear filters + tombol grid/list.
  - Widget di `lib/widgets/project/project_detail_header.dart`. `_buildStatsCard`, `_buildFilterBar`, `_buildStatItem`, dan `_isSearching` dihapus (layar −438/+201 baris). FAB "Add Data" tetap hijau (palet app).
  - Test 960 → 973; analyze 0 error / 29 warning. Tampilan utuh layar belum dirender di test (butuh DB) → cek di HP (Checkpoint B).
- [ ] T5: Daftar project: judul + Sync all, cari, chip All/Unsynced/From server, kartu bertag, FAB Create Project.
- [ ] T6: Buat project: sheet pilih sumber + layar New project (segmented geometri, kartu field berlencana tipe, Add Field).

### Checkpoint B
- [ ] Test hijau; (User, di HP) tampilan ketiga halaman.

## Fase 3 — Alat ukur
- [ ] T7: Edit & tambah titik ukur lewat koordinat (dialog lat/lon, daftar titik, peta bergeser) di tiga layar peta.

### Checkpoint C — Selesai
- [ ] Test hijau; (User, di HP) ukur jarak dengan titik yang diketik/diedit.

## Dibawa dari plan sebelumnya (Form & aturan project) — semua tugas user
- [ ] (User, di HP) project dengan tipe baru: isi, simpan, sync, pull di HP kedua; tipe tak dikenal tidak berubah.
- [ ] (User, di browser) tampilan & edit atribut tipe lama dan baru.
- [ ] (User) CI: `tests_project_rules_db`, `tests_rules_lock_db`, `tests_project_owner_db`, `tests_feature_style_db`, `tests_verification`, `tests_tile_style_db`, `tests_photo_download_db`.
- [ ] (User, di HP) point akurasi buruk ditolak; tracking rata-rata buruk → push ditolak → hapus titik → sync berhasil; duplikat lokal diblokir, duplikat dari HP lain ditolak server.
- [ ] (User) uji manual builder web (buat project, seret, pratinjau, aturan, simpan, pull di HP).
- [ ] (User) Deploy berurutan: backend (termasuk migrasi `0021`–`0023`) → dashboard → rilis app.
- [ ] (User, di HP) style per feature: blok bersebelahan, polygon bertumpuk, slider ukuran point, zoom di blok besar, Style di sheet Tracking Aktif, sync ke HP kedua, upgrade DB v6 → v7.
- [ ] (User, di browser) pilihan "Warna peta" (Status/Style) setelah backend ter-deploy.
