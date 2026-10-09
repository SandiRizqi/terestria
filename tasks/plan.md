# Rencana: Halaman Project — Tampilan List, Pilih & Hapus Data, Layout Baru, Edit Koordinat Alat Ukur

Status: disusun 2026-10-08 dari permintaan user (template gambar 05–08); dikerjakan per task lewat `/agent-skills:build`.
Plan sebelumnya: `tasks/plan-form-rules.md` (arsip lokal; versi git ada di riwayat `tasks/plan.md`). Item manual yang belum selesai dibawa ke `tasks/todo.md`.

## Permintaan
1. Layout halaman project mengikuti template (daftar project, buat project, detail project), tapi **fungsi dan palet warna `AppTheme` tetap**.
2. Data project bisa dilihat sebagai **grid** (yang sekarang) atau **list** seperti template.
3. **Pilih data** satu per satu atau **pilih semua**, dengan checklist.
4. **Hapus data terpilih** dan **kosongkan data lokal**, selalu dengan dialog peringatan.
5. Alat ukur peta: titik yang diambil dengan ketuk peta bisa **diedit koordinatnya** (ketik lat/lon), sehingga lokasi koordinat terlihat di peta dan jaraknya terukur.

## Kondisi sekarang
- `lib/screens/project/project_detail_screen.dart` (3.480 baris):
  - data tampil sebagai `GridView` 2 kolom berisi `GeoDataListItem` (`lib/widgets/geo_data_list_item.dart`);
  - hapus hanya satu per satu lewat `_deleteGeoData`: hanya record milik sendiri, dialog membedakan record yang sudah/belum di server;
  - hapus selalu lokal (`StorageService.deleteGeoData` → `DatabaseService.deleteGeoData`, ikut menghapus konflik).
- `lib/screens/project/projects_screen.dart` (1.218 baris) + `lib/widgets/project_card.dart`: daftar project.
- Alat ukur: `MapToolsController` / `MapToolsPanel` / `MapToolsLayer` (`lib/widgets/map/tools/`), disambung lewat mixin `MapToolsHost` di tiga layar peta (koleksi data, navigasi, peta notifikasi). Titik hanya bisa ditambah dengan ketuk peta; mode `coordinate` hanya menampilkan koordinat.

## Keputusan desain
1. **Palet tetap.** Warna hanya dari `AppTheme` (hijau `primaryGreen`, `warningColor`, `errorColor`, `pointColor`/`lineColor`/`polygonColor`). Warna teal/kuning template diganti padanannya di `AppTheme`.
2. **Grid tetap jadi tampilan bawaan.** Pilihan grid/list disimpan di `SharedPreferences`, berlaku untuk semua project di HP itu.
3. **Baris list** (template 08):
   - ikon geometri;
   - judul `recordTitle`;
   - baris kedua: isian kedua, ukuran (luas polygon / panjang line, unit dari Settings), dan "pengumpul, waktu" ("you" bila milik user; jam untuk hari ini, "yesterday", lalu tanggal);
   - titik status sync (hijau tersinkron, kuning lokal, merah gagal).

   Ketuk = detail. Menu ⋮ = edit/hapus bila boleh, sama dengan tombol di grid.
4. **Hapus terpilih hanya menghapus dari HP** (keputusan user, 9 Okt 2026). Tidak ada penghapusan di server.
   - Semua record terpilih boleh dihapus dari HP, termasuk record pengumpul lain (record seperti itu pasti berasal dari server).
   - Record yang sudah di server tetap di server dan bisa diambil lagi lewat Pull.
   - Record yang belum di-upload hilang permanen.
   - Dialog menyebut jumlah keduanya sebelum menghapus.
5. **Kosongkan data lokal** (menu project) menghapus record project ini **dari HP saja**.
   - Record yang sudah di server bisa diambil lagi lewat Pull.
   - Record yang **belum di-upload** tidak ikut dihapus, kecuali user mencentang "Also delete N records not uploaded yet (permanent)" di dialog. Bawaannya tidak dicentang.
6. **Hapus banyak dalam satu transaksi DB** (`deleteGeoDataBatch`), supaya tidak setengah terhapus bila gagal di tengah.
7. **Edit koordinat alat ukur.** Kartu hasil menampilkan daftar titik. Ketuk titik → dialog lat/lon (desimal; bisa tempel `lat, lon`; rentang dicek). Ada tombol "Add point by coordinate". Peta bergeser ke titik yang diedit/ditambah, dan hasil ukur dihitung ulang.

## Tasks

### Fase 1 — Data project: list, pilih, hapus
- **T1 — Tampilan list + tombol grid/list.**
  - Isi: widget baru `GeoDataListTile`; helper murni (ringkasan baris kedua, waktu singkat, ukuran); tombol grid/list di baris filter; pilihan disimpan.
  - AC: grid tetap bawaan dan tidak berubah; list menampilkan judul, ringkasan, dan status; pilihan bertahan setelah layar dibuka ulang; edit/hapus/detail tetap jalan dari list.
  - Verifikasi: `flutter test test/utils/record_summary_test.dart test/widgets/geo_data_list_tile_test.dart`; `flutter analyze` pada file yang berubah.
- **T2 — Mode pilih + pilih semua.**
  - Isi: tekan lama item (atau tombol Select) → checkbox di grid & list; bar pilihan berisi jumlah terpilih, Select all, dan batal. "Select all" = semua record yang **terlihat** (setelah filter/cari). Logika pilihan murni dan teruji.
  - AC: tap di mode pilih = centang (bukan buka detail); keluar mode = pilihan kosong; filter berubah → pilihan yang tak terlihat dilepas.
- **T3 — Hapus terpilih + kosongkan data lokal.**
  - Isi: `StorageService/DatabaseService.deleteGeoDataBatch(ids)` (satu transaksi); dialog peringatan dengan rincian (keputusan 4–5); menu "Clear local data".
  - AC: tidak ada yang terhapus tanpa konfirmasi; record belum di-upload hanya terhapus bila dicentang; jumlah di snackbar sesuai isi DB.
  - Verifikasi: test DB (sqflite ffi) untuk batch delete; test widget dialog.

#### Checkpoint A
Test hijau; analyze tidak memburuk; **(User, di HP)** list/grid, pilih, hapus, kosongkan data lokal.

### Fase 2 — Layout seperti template
- **T4 — Detail project (template 08):**
  - judul besar + "Created by … · updated …";
  - kartu statistik ringkas (Type/Records/Fields);
  - banner sync;
  - kotak cari + tombol filter berlencana jumlah filter (menggantikan cari di AppBar);
  - FAB "Add Data".

  Menu Pull/Push/Info/Export dan semua fungsi tetap.
- **T5 — Daftar project (template 05):**
  - judul + tombol "Sync all", kotak cari, chip filter "All n / Unsynced / From server";
  - kartu: ikon geometri, nama, "N records · waktu", tag tipe/status sync/asal server, menu ⋮;
  - FAB "Create Project".

  Fungsi kartu sekarang (termasuk kedip saat tracking aktif) tetap.
- **T6 — Buat project (template 06–07):**
  - sheet "Create Project" dengan tiga sumber (Start from scratch / Import template / From server) yang memanggil fungsi yang sudah ada;
  - layar New project: pilihan geometri bergaya segmented, kartu field dengan lencana tipe, tombol "Add Field" bergaris putus.

#### Checkpoint B
Test hijau; **(User, di HP)** tampilan ketiga halaman.

### Fase 3 — Alat ukur
- **T7 — Edit & tambah titik ukur lewat koordinat.**
  - Isi: `MapToolsController.updatePoint/insert` + validasi koordinat murni; daftar titik di kartu hasil; dialog lat/lon; peta bergeser lewat kait di `MapToolsHost` (dipasang di tiga layar peta).
  - AC: edit titik → hasil jarak/luas berubah sesuai; koordinat di luar rentang/format salah ditolak dengan pesan; mode `coordinate` bisa ketik koordinat lalu peta menuju ke sana.

#### Checkpoint C (selesai)
Test hijau; **(User, di HP)** ukur jarak dengan titik yang diketik/diedit di ketiga layar peta.

## Risiko
| Risiko | Mitigasi |
|---|---|
| `project_detail_screen.dart` sangat besar; perubahan layout bisa merusak fungsi | Widget baru di file sendiri; layar hanya merangkai; test widget untuk aksi penting |
| Data belum di-upload terhapus | Konfirmasi wajib; bawaan tidak menghapus record belum di-upload; transaksi tunggal |
| Pilihan tersembunyi ikut terhapus | "Select all" hanya yang terlihat; pilihan dilepas saat filter berubah |
| Layout template memakai warna lain | Keputusan 1: hanya `AppTheme` |

## Pertanyaan terbuka (dipakai default di atas bila tidak dijawab)
- ~~Keputusan 4–5~~: user memutuskan hapus hanya berlaku di HP (9 Okt). Keputusan 4 diperbarui; keputusan 5 tetap memakai default.
- T6 menyentuh alur buat project; bila hanya halaman daftar & detail yang ingin diubah, T6 dilewati.
