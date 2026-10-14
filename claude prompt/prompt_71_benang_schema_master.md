# Prompt 71 — Stok Benang: Schema `inv`, Module & Role, Master SKU + Lokasi, Landing

Prompt pertama seri 71–77. Baca `claude prompt/prompt_71-77_RUN.md` dan
`claude prompt/benang/module-benang-keputusan-desain.md` dulu.

## 1. Schema & tabel — `sql/inv/create_71_inv_thread.sql` (idempotent, eksekusi langsung)

`CREATE SCHEMA inv` kalau belum ada. Semua tabel punya kolom audit standar
(`created_at/created_by/updated_at/updated_by/deleted_at/deleted_by`), unique = filtered
index `WHERE deleted_at IS NULL`.

```sql
inv.thread_types        (thread_type_id PK, code varchar(20) UQ, name varchar(50), sort_order int)
inv.thread_brands       (thread_brand_id PK, name varchar(100) UQ)
inv.thread_locations    (thread_location_id PK, code varchar(20) UQ, name varchar(100) null, sort_order int, is_active bit default 1)
inv.thread_items        (thread_item_id PK,
                         sku_code varchar(40) UQ,          -- dibuat sistem, lihat §3
                         thread_type_id FK, thread_brand_id FK,
                         color_name varchar(100), color_code varchar(30),
                         cone_size varchar(10) CHECK IN ('KECIL','BESAR'),
                         photo_path varchar(255) null,     -- nama file GUID di disk
                         is_active bit default 1)
inv.thread_stocks       (thread_stock_id PK, thread_item_id FK, thread_location_id FK,
                         qty_whole int not null default 0,
                         UQ (thread_item_id, thread_location_id) filtered)
                         -- saldo whole per SKU per rak; HANYA diubah oleh SP movement (Prompt 72)
inv.thread_split_cones  (thread_split_cone_id PK,
                         cone_code varchar(20) UQ,          -- 'SP-000001', serial global, applock 'thread_split_seq'
                         thread_item_id FK,
                         weight_gram int not null,          -- netto, tanpa tube
                         thread_location_id FK null,        -- null saat ISSUED
                         status varchar(10) CHECK IN ('IN_STOCK','ISSUED','EMPTY'),
                         issued_to_resource_id FK resources null,
                         issued_project_id FK projects null)
inv.thread_movements    (thread_movement_id PK,
                         movement_type varchar(20) CHECK IN
                           ('RECEIVE','ISSUE','RETURN','ISSUE_SPLIT','RETURN_SPLIT','MOVE','MOVE_SPLIT','ADJUST','ADJUST_SPLIT','EMPTY'),
                         thread_item_id FK,
                         thread_split_cone_id FK null,
                         from_location_id FK null, to_location_id FK null,
                         qty_whole int null,                 -- + / − ; untuk tipe whole
                         weight_gram int null,               -- untuk tipe split (berat saat itu)
                         resource_id FK resources null,      -- line tujuan/asal
                         project_id FK projects null,
                         reason_code varchar(30) null,       -- hanya ADJUST*, lihat §2
                         note varchar(500) null,
                         opname_line_id int null)            -- FK ditambah di Prompt 74
inv.thread_reason_codes (code varchar(30) PK, name varchar(100), requires_note bit, sort_order int)
```

Index: `IX_thread_movements_item_date (thread_item_id, created_at)`,
`IX_thread_movements_type_date (movement_type, created_at)`,
`IX_thread_split_cones_item_status (thread_item_id, status)`.

View `inv.v_thread_item_stock`: per SKU → `qty_whole_total`, `split_count_in_stock`,
`split_gram_in_stock`, `split_count_issued`, daftar lokasi (STRING_AGG `code` yang qty>0).

## 2. Seed — `sql/inv/seed_71_inv_thread.sql` (idempotent)

- `thread_types`: POLY "Poly", COTTON "Cotton", SPUN "Spun", NYLON "Nylon".
- `thread_reason_codes`: HILANG "Hilang" (0), SALAH_INPUT "Salah input sebelumnya" (0),
  PINDAH_TAK_TERCATAT "Pindahan belum dicatat" (0), MASUK_TAK_TERCATAT "Masuk belum dicatat" (0),
  RUSAK "Rusak / tidak terpakai" (0), STOK_AWAL "Stok awal" (0), LAINNYA "Lainnya" (requires_note 1).
- Module (pola `seed_*_module.sql`): Code `INV_THREAD`, Name `Stok Benang`,
  Category `Gudang`, Route `gudang/benang`, Icon `fe fe-layers`, SortOrder 300.
  Assign ke user Role = Admin.
- Lokasi: tidak di-seed; dibuat dari halaman master.

## 3. SP master

| SP | Isi |
|---|---|
| `inv.SIS_ThreadType_Manage` | @Action CREATE/UPDATE/DELETE |
| `inv.SIS_ThreadType_List` | semua aktif, urut sort_order |
| `inv.SIS_ThreadBrand_Manage` | CREATE/UPDATE/DELETE; CREATE boleh dipanggil inline dari form SKU |
| `inv.SIS_ThreadBrand_List` | |
| `inv.SIS_ThreadLocation_Manage` | CREATE/UPDATE/DELETE/SETACTIVE; DELETE ditolak kalau ada `thread_stocks.qty_whole > 0` atau split IN_STOCK di lokasi itu (RAISERROR pesan Indonesia) |
| `inv.SIS_ThreadLocation_List` | + kolom `item_count`, `qty_whole_total`, `split_count` |
| `inv.SIS_ThreadItem_Manage` | CREATE/UPDATE/DELETE/SETACTIVE/SETPHOTO. CREATE membuat `sku_code` = `BN-<type.code 3 huruf>-<brand 3 huruf, huruf&angka saja, uppercase>-<color_code>-<K|B>`; kalau bentrok tambah `-2`, `-3`. DELETE ditolak kalau pernah ada movement. |
| `inv.SIS_ThreadItem_List` | paged + search (warna, kode warna, merk, sku_code) + filter type/location + sort; join `v_thread_item_stock` |
| `inv.SIS_ThreadItem_GetById` | detail + stok per lokasi (result set 2) + split cones (result set 3, IN_STOCK dan ISSUED) |
| `inv.SIS_ThreadItem_GetBySku` | untuk hasil scan `TB:<sku_code>` |

Guard di SP: `cone_size`, `thread_type_id`, `thread_brand_id` wajib valid; pesan RAISERROR
Indonesia.

## 4. API

`ThreadStockController`, route `api/gudang/benang`, `[Authorize]` + `[RequireModule("INV_THREAD")]`.
Endpoint master types/brands/locations/items (list, get, post, put, delete, setactive).

**Foto SKU**: `POST api/gudang/benang/items/{id}/photo` (multipart). Pola upload gambar yang
sudah ada: ImageSharp, tapi untuk benang **max 800px, JPEG 80**; simpan ke folder upload
`thread/` dengan nama GUID; file lama dihapus saat diganti; `SETPHOTO` menyimpan path.
Satu foto per SKU. `GET` foto lewat static files seperti upload lain.

## 5. Role Admin Gudang

Telusuri dulu bagaimana role & redirect setelah login diimplementasi (cari implementasi role
satpam / gate dari Prompt 70 bila ada; kalau belum ada, lihat bagaimana `Role` di `users`
dan redirect di `Login.razor` / `MainLayout`). Buat:

- Role baru `WAREHOUSE` (tampilan "Admin Gudang").
- User dengan role ini: setelah login langsung ke `/gudang/benang`; sidebar hanya
  menampilkan module yang dimiliki (sudah begitu kalau menu dinamis per module).
- Kalau belum ada mekanisme landing-per-role, tambahkan kolom `home_route varchar(100) null`
  di tabel role (atau `users` kalau role bukan tabel) lewat `sql/inv/alter_71_home_route.sql`,
  dan pakai di redirect login. Admin tetap ke dashboard biasa.

## 6. Client — halaman

**Baca dulu** `claude prompt/benang/mockup/Main.dc.html`, `Sku.dc.html`, dan
`TabletBeranda.dc.html` — layout, teks, dan warna mengikuti mockup (aturan di RUN.md).
Buat `wwwroot/css/benang.css` di prompt ini untuk dipakai seluruh seri.

Folder `Pages/Gudang/Benang/`. Semua halaman **responsif**: ≤ 899px satu kolom (mockup
HP), ≥ 900px dua panel (mockup `TabletBeranda.dc.html`). Pakai Bootstrap grid yang sudah
ada; tidak perlu library baru.

| Route | Halaman | Mockup |
|---|---|---|
| `/gudang/benang` | Landing: tombol scan (placeholder sampai Prompt 72), kotak cari, tiga tombol aksi (Ambil/Kembali/Opname — link ke route yang dibuat prompt berikutnya, tampilkan tapi disabled dengan tooltip "Prompt berikutnya" sampai ada), daftar SKU (thumbnail, nama·kode, type·merk·kones, lokasi, qty whole, +n split). Tablet: daftar di kiri, detail SKU di kanan. | `Main.dc.html`, `TabletBeranda.dc.html` |
| `/gudang/benang/sku/{id}` | Detail SKU: foto besar + tombol ganti foto (input `capture="environment"`), ringkasan whole/split, tabel stok per lokasi, daftar split cones, tombol Edit. | `Sku.dc.html` |
| `/gudang/benang/sku/baru`, `/edit/{id}` | Form SKU: jenis (dropdown), merk (`SearchableSelect` + "tambah merk baru" inline), warna, kode warna, jenis kones (toggle KECIL/BESAR), foto (opsional, boleh dilengkapi belakangan). | — |
| `/gudang/benang/lokasi` | Master lokasi: daftar + form inline (code, nama), aktif/nonaktif. | — |
| `/gudang/benang/master` | Tab kecil: jenis benang, merk. | — |

Thumbnail SKU tanpa foto → kotak abu bertuliskan "no foto" seperti mockup. Nama user login
tampil di header landing ("Gudang · <nama>").

Komponen bersama `ThreadSkuCard.razor` (dipakai di daftar landing, hasil scan, opname).

## 7. Verifikasi

- Build sukses; DDL & seed tereksekusi; module tampil di menu user Admin.
- Buat 1 user role WAREHOUSE lewat script `sql/inv/seed_71_user_gudang.sql` (username
  `gudang`, password awal `gudang123` — hash dengan fungsi yang sama seperti user lain;
  kalau hashing hanya ada di C#, buat endpoint sementara TIDAK boleh — cukup catat di
  ringkasan bahwa user dibuat lewat halaman User Management).
- Jangan buat halaman movement/opname/label di prompt ini.
