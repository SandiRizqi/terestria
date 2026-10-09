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
- [x] T5: Layout daftar project seperti template 05.
  - AppBar terang: judul besar "Projects", indikator koneksi (ikon), tombol **"Push all"**. Isinya sama dengan menu lama "Push to Server" (hanya struktur project yang belum ada di server), jadi labelnya tidak "Sync all".
  - Kotak cari selalu tampil (menggantikan cari di AppBar). Chip **All n / Unsynced / From server**:
    - "Unsynced" = project belum di server atau ada record belum ter-upload;
    - "From server" = project dibuat user lain.
  - Kartu: ikon geometri, nama, "**N records · waktu**" (aktivitas terakhir project/record), deskripsi 1 baris, dan tag: tipe; status (Sync failed / N unsynced / Local / Synced); From server; REC/PAUSED/NOT SAVED (key sama). Tombol collectors/edit/hapus pindah ke menu ⋮ "Project actions"; edit tetap hanya untuk pembuat ("Only the creator can edit"). Chip collectors, tanggal buat, dan pembuat tidak lagi di kartu (collectors tetap bisa dilihat lewat menu).
  - Jumlah per project dari satu query terkelompok (`DatabaseService.getProjectDataStats`); aturan filter/tag/subjudul murni di `lib/utils/project_list.dart`. Kembali dari detail project selalu memuat ulang (jumlah record bisa berubah). FAB "Create Project".
  - `_syncProjectsFromServer` sejak sebelumnya tidak terjangkau dari UI (menu lama tak punya item pull); kini diberi `ignore: unused_element` + catatan, menunggu keputusan user.
  - Test 973 → 986; analyze 0 error / 29 warning.
- [x] T6: Alur buat project seperti template 06–07.
  - **Sheet "Create Project"** (`showCreateProjectSourceSheet`) menggantikan dialog lama. Pilihannya memanggil fungsi yang sama dengan dulu:
    - Start from scratch → layar New project;
    - Import template → impor .json;
    - From server → dialog cloud ("Download a project assigned to you"; data tetap di-Pull dari detail);
    - Cancel.
  - **Layar New/Edit project:**
    - AppBar terang dengan ✕, judul, dan tombol **Save** hijau (spinner saat menyimpan);
    - label di atas isian Project Name/Description;
    - Geometry Type bergaya segmented (terkunci saat edit, dengan tanda "Cannot be changed");
    - header "FORM FIELDS · n" + "Drag to reorder";
    - kartu field: pegangan seret (seret hanya lewat pegangan, ketuk kartu = edit), label + `*` merah bila wajib, ringkasan (opsi / batas angka + satuan / jumlah foto / "Required" / keterangan tipe, + "Unique key"), lencana tipe (`text`, `dropdown`, …), tombol hapus;
    - tombol "Add Field" bergaris putus;
    - Project rules tetap.
  - Komponen di `lib/widgets/project/create_project_parts.dart` dan `create_project_source_sheet.dart`. Pemilih radio & kartu ListTile lama dihapus (layar −354 baris bersih).
  - Test 1000 → 1013; analyze 0 error / 29 warning.

- [x] Perbaikan (laporan user 9 Okt): tombol AppBar terang tidak terlihat.
  - Penyebab: tema app memasang `iconTheme`/`titleTextStyle` putih secara eksplisit, dan itu mengalahkan `foregroundColor` gelap. Akibatnya tombol kembali/Export/⋮/✕ dan judul "New/Edit project" putih di atas latar terang.
  - Perbaikan: `lightAppBar()` (`lib/theme/light_app_bar.dart`) menimpa `iconTheme`, `actionsIconTheme`, dan `titleTextStyle` menjadi `textPrimary`. Dipakai di daftar, detail, dan buat/edit project.
  - Test (dengan tema app sungguhan) gagal sebelum perbaikan: ikon ✕ bernilai putih.
  - Test 1013 → 1015; analyze 0 error / 29 warning.

- [x] Perbaikan tata letak (laporan user 9 Okt):
  - **Detail project — header tetap:** judul, statistik, banner, cari/filter, dan baris jumlah tidak lagi ikut tergulir (hanya daftar data yang bergulir; kebalikan dari keputusan T4).
  - **Detail project — tanpa pita kosong di bawah:** body tidak dipotong `SafeArea` bawah; daftar bergulir sampai tepi layar dengan padding bawah = FAB + bilah navigasi HP.
  - **Ringkas:** kartu Type/Records/Fields satu baris (≤ 44 px, sebelumnya 71 px); judul 24 → 20; kotak cari dan jarak antarbagian dirampingkan.
  - **Panel kontrol peta koleksi data:**
    - tinggi panel kini pas dengan isinya (`BottomControlsMetrics.height`): isi ringkas 76, diperluas 80, tracking 144;
    - dulu 84/128/184 ditambah padding 12, lalu bilah navigasi ditumpuk di atasnya;
    - ruang bawah = bilah navigasi HP (minimal 8);
    - label tombol panel dikunci satu baris (mengecil bila tak muat), karena "Add point (crosshair)" dulu bisa dua baris;
    - layar memakai rumus yang sama untuk posisi tombol peta.
  - **Test:** layar detail kini bisa di-pump di test (data gagal dimuat tanpa DB → kosong). Test "header di luar area gulir" dan "daftar sampai tepi bawah" — yang kedua terbukti gagal dengan perilaku lama (692 vs 740 px).
  - Test 1015 → 1024; analyze 0 error / 29 warning.

- [x] Perbaikan panel kontrol peta koleksi data (laporan user 9 Okt, dengan tangkapan layar iPhone):
  - **Penyebab "masih ada space putih & tombol terpotong":** angka tinggi tetap dari test tanpa tema app. Padding tombol dari tema membuat tombol 56 (bukan 52), sehingga baris bawah terpotong 8 px, lalu di bawahnya masih ada 34 px home indicator berwarna putih.
  - **Kartu mengambang:**
    - jarak bawah = jarak kiri/kanan (12) sesuai permintaan user;
    - bilah navigasi bertombol (Android 3 tombol, ≥ 40 dp) tidak ditutup — kartu tepat di atasnya;
    - area di bawah kartu tembus ke peta.
  - **Tinggi mengikuti isi:** diukur (`onHeightChanged`), bukan angka tetap; tombol 48. Kolom tombol peta di kanan ikut tinggi terukur (`ValueListenableBuilder`).
  - **Point & mode gambar:** langsung [Add point][Undo][Clear] satu baris, tanpa sembunyikan (tak ada tombol track).
  - **Line/polygon mode GPS:** bisa disembunyikan lewat tombol ⌄/⌃, ketuk pegangan, atau geser. Geser dihitung sejak jari menyentuh (termasuk di atas tombol) dan geser cepat ikut dihitung — dulu flick pendek diabaikan.
  - Sambungan layar (`d99aba1`, di-commit user) + kartu final di commit ini.
  - Test (tema app asli, layar iPhone 390×844): tombol utuh di kartu, jarak bawah 12/48, tanpa pita putih, sembunyikan/munculkan, tinggi terlapor. Test 1024 → 1050; analyze 0 error / 29 warning.

- [x] Tombol Select pindah dari menu ⋮ ke baris jumlah record (permintaan user 9 Okt):
  - sejajar tombol grid/list tapi grup sendiri (bentuk pil yang sama);
  - aktif (hijau) selama mode pilih, ketuk lagi = keluar; nonaktif bila tak ada record;
  - grid/list kini selalu menempel ke kanan (dulu `Flexible` + `Spacer` menyisakan celah bila teks jumlah pendek — terbukti 350 vs 360 px).
- [x] AppBar mode pilih memakai hijau utama aplikasi (`primaryGreen`, dulu `darkGreen` yang kehijauan-biru).
  - Test 1050 → 1056; analyze 0 error / 29 warning.

### Checkpoint B
- [x] Test hijau (1013); analyze 0 error / 29 warning (sama dengan baseline 8 Okt).
- [ ] (User, di HP) tampilan ketiga halaman: daftar project, detail project, buat/edit project (termasuk sheet pilih sumber).

## Fase 3 — Alat ukur
- [x] T7 (dikerjakan sebelum T6, permintaan user 9 Okt): edit & tambah titik alat ukur lewat koordinat.
  - **Kartu hasil:**
    - mode Distance/Area/Bearing/Radius menampilkan daftar titik bernomor (koordinat 6 desimal), ketuk = edit;
    - mode Coordinate: ketuk hasil koordinat = edit;
    - tombol "Add by coordinate" / "Enter coordinate".
  - **Dialog Latitude/Longitude:**
    - derajat desimal; koma desimal diterima;
    - tempel "lat, lon" / "lat lon" / "lat;lon" di kolom Latitude mengisi keduanya;
    - rentang dicek per kolom ("Latitude must be between -90 and 90"), dialog tetap terbuka bila salah.
  - **Setelah simpan:** hasil ukur dihitung ulang (`MapToolsController.updatePoint`), lalu peta bergeser ke titik itu (zoom minimal 16, tidak memperkecil zoom). Lewat `MapToolsHost.mapToolsMapController`, di-override di layar koleksi data, navigasi, dan peta notifikasi.
  - Logika murni di `coordinate_input.dart`.
  - Test 986 → 1000; analyze 0 error / 29 warning.
- [x] Tambahan (permintaan user 9 Okt, `79958e1`): fungsi "Pull from server" daftar project yang tak punya tombol dihapus, bersama import/field yang ikut tak terpakai.

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
