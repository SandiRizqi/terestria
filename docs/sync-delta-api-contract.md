# API Contract — Delta Sync `updated_after` (mobile geodata pull)

Dokumen ini untuk tim backend. Menjelaskan perubahan kecil yang dibutuhkan agar
klien mobile bisa **delta sync** (hanya menarik record yang berubah), beserta
schema request/response yang **sudah dipakai klien saat ini** supaya tidak ada
breaking change.

Status: **usulan** — menunggu implementasi & deploy server.
Terkait: `tasks/plan.md` §13–18 (Fase 6), `lib/services/sync_service.dart`
(`pullGeoDataFromServer`), `lib/services/sync_watermark_service.dart`.

---

## 1. Endpoint

```
GET /mobile/geodata/by-project/
```

### Query parameters

| Param | Wajib | Contoh | Keterangan |
|---|---|---|---|
| `project_id` | ya | `1772757095813` | ID project. |
| `page` | tidak | `1` | Halaman (paginasi). Default `1`. |
| `updated_after` | **BARU, opsional** | `2026-06-21T10:37:01.075171Z` | Kembalikan hanya record dengan `updated_at >= updated_after`. **Inklusif.** Format ISO8601 **UTC**. |

Contoh request delta:
```
GET /mobile/geodata/by-project/?project_id=1772757095813&page=1&updated_after=2026-06-21T10:37:01.075171Z
```

### Aturan `updated_after` (WAJIB dipatuhi)

1. **Inklusif** (`updated_at >= updated_after`), bukan `>`. Klien sudah dedup
   record di batas waktu, jadi inklusif aman dan mencegah record di batas
   granularitas jam terlewat.
2. Bila **tidak** ada param `updated_after` → perilaku **lama**: kembalikan
   semua record project (full pull). **Backward-compatible** — klien lama &
   sync pertama tetap jalan.
3. Field acuan = `updated_at` (bukan `created_at`).
4. **Urutkan hasil `updated_at` menaik (ASC)** agar paginasi + watermark stabil
   (lihat §4).
5. Nilai waktu diperlakukan sebagai UTC.

---

## 2. Response — envelope

HTTP `200 OK`, body JSON:

```jsonc
{
  "success": true,
  "message": "GeoData retrieved successfully",
  "data": [ /* array record, lihat §3 */ ],
  "total_pages": 3,      // WAJIB: jumlah total halaman untuk (project_id + filter)
  "page": 1              // opsional, informatif
}
```

Field yang **dibaca klien**: `data` (array) dan `total_pages` (int). Klien
melakukan loop `page` dari 1..`total_pages`. `total_pages` harus mencerminkan
hasil **setelah** filter `updated_after` diterapkan.

Bila project tak punya record berubah:
```json
{ "success": true, "message": "No changes", "data": [], "total_pages": 1 }
```

---

## 3. Response — schema satu record (geodata)

Klien mem-parse via `GeoData.fromJson` (mendukung `snake_case` **dan**
`camelCase`; disarankan `snake_case`):

```jsonc
{
  "id": "8f796837-7c4e-499c-a78e-6ae0b95295ab",   // string, WAJIB (idempotency key)
  "project_id": "1772757095813",                   // string, WAJIB
  "collected_by": "hasyim.amiruddin",              // string|null
  "form_data": { /* lihat §3.1 */ },               // object, WAJIB
  "points": [ /* lihat §3.2 */ ],                  // array, WAJIB (boleh 1..n)
  "created_at": "2026-06-21T10:37:01.073748+00:00",// ISO8601, WAJIB
  "updated_at": "2026-06-21T10:37:01.073753+00:00",// ISO8601, WAJIB (dasar delta)
  "is_synced": true,                                // bool
  "synced_at": "2026-06-21T10:37:01.075171+00:00"  // ISO8601|null
}
```

> `updated_at` adalah kontrak paling penting: harus **naik setiap kali record
> berubah** di server, karena klien menyimpannya sebagai watermark.

### 3.1 `form_data`

Objek key-value sesuai definisi field project. Untuk field bertipe **photo**,
nilainya adalah **array objek PhotoMetadata**:

```jsonc
"Photo": [
  {
    "name": "IMG_1781838874234.jpg",
    "created": "2026-06-19T11:14:34.236384",
    "updated": "2026-06-21T18:36:50.418154",
    "localPath": "/data/.../photos/originals/IMG_1781838874234.jpg", // path uploader; diabaikan device lain
    "serverKey": "Production/1782038210_IMG_1781838874234.jpg",       // identitas stabil OSS
    "serverUrl": "https://tap-gis.oss-...aliyuncs.com/Production%2F...?OSSAccessKeyId=...&Expires=...&Signature=..."
  }
]
```

Aturan photo:
- `serverKey` = **identitas stabil** objek di OSS. **Wajib terisi** untuk foto
  yang sudah tersimpan. Klien memakai `serverKey` untuk memutuskan foto sudah
  ter-upload atau belum.
- `serverUrl` = signed URL. **Regenerasi setiap fetch** (jangan simpan yang
  kedaluwarsa); klien memakainya hanya untuk mengunduh saat itu juga.
- Field non-foto: nilai apa adanya (string/number/bool).

### 3.2 `points`

Klien mem-parse via `GeoPoint.fromJson`:

```jsonc
{
  "latitude": 2.2395458,        // double, WAJIB
  "longitude": 116.9953588,     // double, WAJIB
  "altitude": null,             // double|null
  "accuracy": null,             // double|null
  "speed": null,                // double|null (km/h)
  "timestamp": "2026-06-19T11:13:31.843740", // ISO8601, WAJIB
  "fixQuality": null,           // string|null (fix/float/autonomous)
  "satelliteCount": null        // int|null
}
```

---

## 4. Paginasi + delta (stabilitas)

- Urutkan `updated_at ASC` (lalu `id ASC` sebagai tie-breaker) agar halaman
  konsisten antar-request.
- `total_pages` dihitung atas hasil **terfilter**.
- Klien menyimpan watermark = `updated_at` **tertinggi** dari seluruh record
  yang berhasil ditarik, dan hanya memajukannya **setelah semua halaman project
  tsukses**. Jadi bila page ke-N gagal, sinkron berikutnya mengulang dari
  watermark lama (aman, tak ada record terlewat).

---

## 5. Yang TIDAK berubah (tetap seperti sekarang)

- **Push** `POST /mobile/geodata/` — payload tetap; server tetap menyimpan
  `form_data` termasuk `serverKey`/`serverUrl` per foto.
  - *Saran hardening (opsional, terpisah):* server menolak/menandai payload
    yang punya foto dengan `serverKey: null` agar tidak ada data "synced
    palsu".
- **Upload foto** `POST /uploadfile/` (multipart, field `file`) → response:
  ```json
  { "success": true, "file_url": "https://.../signed-url", "key": "Production/....jpg" }
  ```
  Klien menyimpan `key` → `serverKey`, `file_url` → `serverUrl`.

---

## 6. Batasan diketahui (di luar scope kontrak ini)

- **Deletion server-side tidak tercakup** delta ini (klien tak tahu record
  dihapus di server). Sama seperti perilaku full-pull sekarang. Bila nanti
  perlu, tambahkan mekanisme tombstone (mis. `deleted_after` / flag `deleted`).
