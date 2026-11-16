# Prompt 91 — CCTV: Schema, Module, Master Kamera

Baca `claude prompt/cctv/module-cctv-keputusan-desain.md` dan mockup
`claude prompt/cctv/mockup/Kamera.dc.html`.

## 0. Inspeksi dulu

Ringkas di awal jawaban (dan di laporan):
- Server + database target dari `appsettings*.json`.
- Pola seed module terbaru (`sql/inv/seed_71_inv_thread_module.sql`): kolom `Modules`
  yang dipakai (termasuk `SubCategory`), dan kategori menu yang ada.
- Pola controller + service + DTO module ber-schema (lihat module benang `inv`).
- Nama tabel & kolom kunci `resources` dan `divisions`.
- Apakah `http://192.168.8.233:9997/v3/paths/list` terjangkau dari mesin ini.

## 1. SQL — folder `sql/cctv/`

`create_schema_cctv.sql` (idempotent):

**`cctv.cameras`**
- `camera_id` INT IDENTITY PK
- `name` NVARCHAR(100) NOT NULL — nama tampil
- `area` NVARCHAR(50) NULL — teks bebas (Cutting, Sewing, Gudang, …)
- `mtx_path` NVARCHAR(50) NOT NULL — path MediaMTX, mis. `cam8_83`; unik (filtered
  index `WHERE deleted_at IS NULL`); hanya huruf/angka/`_`/`-` (CHECK)
- `ip_address` NVARCHAR(45) NULL, `serial_no` NVARCHAR(30) NULL,
  `nvr_channel` INT NULL — inventaris saja
- `sort_order` INT NOT NULL DEFAULT 0
- `is_visible` BIT NOT NULL DEFAULT 1 — tampil di grid live
- `note` NVARCHAR(200) NULL
- kolom audit standar + soft delete

**`cctv.camera_links`** — kaitan kamera ke produksi
- `camera_link_id` INT IDENTITY PK, `camera_id` FK
- `resource_id` INT NULL (FK resources), `division_id` INT NULL (FK divisions) —
  tepat satu yang terisi (CHECK)
- kolom audit standar + soft delete; unik per (camera, resource) dan (camera, division)
  di baris hidup

**SP**
- `cctv.SIS_Camera_Manage` `@Action` = `CREATE` | `UPDATE` | `DELETE` | `SYNC_ADD`
  (`SYNC_ADD`: insert kamera baru dengan `name = mtx_path` kalau path belum ada;
  path yang sudah ada dilewati tanpa error) | `SET_LINKS` (ganti seluruh tautan satu
  kamera dari dua daftar id dipisah koma: `@ResourceIds`, `@DivisionIds`).
- `cctv.SIS_Camera_List` (`@OnlyVisible` BIT = 0, `@Area` = NULL) — urut `sort_order`,
  `name`; sertakan ringkasan tautan (nama resource/divisi digabung koma).
- `cctv.SIS_Camera_Get` (`@CameraId`) — detail + result set tautan.
- `cctv.SIS_Camera_Lookup` — daftar resource dan divisi hidup untuk form.

`seed_91_cctv_module.sql`: module `CCTV`, nama "CCTV", route `cctv`, icon
`fe fe-video`, kategori mengikuti yang paling cocok dari hasil inspeksi.
**Jangan** assign ke user mana pun — owner mencentang sendiri.

## 2. API

- Section baru di `appsettings.json` (nilai contoh; dev boleh override di
  `appsettings.Development.json` ke `192.168.8.233`):
  ```json
  "Cctv": {
    "MtxApiBaseUrl": "http://127.0.0.1:9997",
    "MtxHlsBaseUrl": "http://127.0.0.1:8888",
    "MtxWebRtcBaseUrl": "http://127.0.0.1:8889",
    "MtxPlaybackBaseUrl": "http://127.0.0.1:9996",
    "StreamTokenSecret": "",
    "StreamTokenMinutes": 10
  }
  ```
  `StreamTokenSecret` kosong di repo; dipakai mulai Prompt 92.
- `CctvMediaMtxClient` (HttpClient bernama, timeout 5 detik): `GetPathsAsync()` →
  daftar `{ name, ready }` dari `/v3/paths/list` (ikuti paging kalau ada). Kalau
  MediaMTX tidak terjangkau: kembalikan daftar kosong + flag `Reachable = false`,
  jangan lempar error ke user.
- `CctvCameraController` (`api/cctv/cameras`, `[RequireModule("CCTV")]`):
  - `GET` (query `onlyVisible`, `area`) — gabungkan hasil SP dengan status MediaMTX:
    tiap kamera dapat `Status` = `ONLINE` | `OFFLINE` | `UNKNOWN` (MediaMTX tidak
    terjangkau).
  - `GET {id}`, `POST`, `PUT {id}`, `DELETE {id}`, `PUT {id}/links`
  - `POST sync` — ambil path dari MediaMTX → `SYNC_ADD` tiap path; jawab jumlah
    ditambahkan.
  - `GET lookup` — resource + divisi.
- DTO di `TerakarsaApp.Shared/Cctv/`.

## 3. Client

- Layout module: bar atas dengan tab **Live · Playback · Kamera** seperti mockup
  (komponen bersama `Pages/Cctv/Shared/CctvTabs.razor`). Live dan Playback untuk
  sementara halaman kosong bertuliskan "Menyusul" (diisi Prompt 92–93).
- `/cctv/kamera` — tabel sesuai `Kamera.dc.html`: Nama kamera, Area, Station terkait,
  Path, IP, NVR, Status, Tampil, tombol Ubah. Tombol **Ambil kamera baru dari server**
  (panggil `sync`, toast "n kamera baru ditambahkan") dan **Tambah manual**.
- Form ubah/tambah: nama, area (input dengan saran dari area yang sudah ada), urutan
  tampil, path (hanya bisa diisi saat tambah manual), IP, serial, channel NVR, tampil
  di live (ya/tidak), catatan, dan pilihan banyak untuk **Station / line** dan
  **Divisi** yang terlihat di kamera.
- Kalau MediaMTX tidak terjangkau, tampilkan banner "Server rekaman tidak terjangkau —
  status kamera tidak diketahui".
- Menu sidebar mengarah ke `/cctv` (→ Live).

## 4. Verifikasi

1. Build sukses; script dieksekusi dan aman dijalankan ulang.
2. Sync dua kali: kali kedua menambah 0 kamera.
3. Simpan tautan kamera ke 1 resource + 1 divisi, baca ulang → tampil.
4. User tanpa module `CCTV` → API menolak, menu tidak muncul.

## Yang TIDAK boleh dilakukan

- Jangan membuat kolom untuk user/password/kode verifikasi kamera.
- Jangan menampilkan video apa pun di prompt ini.
- Jangan assign module ke user lewat seed.

Isi bagian "Prompt 91" di laporan, lalu commit.
