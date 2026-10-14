# Prompt 72 — Stok Benang: Movement (Terima, Ambil, Kembali & Timbang, Pindah Rak) + Scan

Dijalankan SETELAH Prompt 71.

## 1. SP — `sql/inv/sp_72_ThreadMovement.sql`

### `inv.SIS_ThreadMovement_Manage` (@Action)

Semua action berjalan dalam satu transaksi, menulis `thread_movements` **dan** memperbarui
saldo (`thread_stocks` / `thread_split_cones`). Saldo tidak boleh minus
(`RAISERROR('Stok di rak %s hanya %d kones.', 16, 1, ...)`). `created_by` = @UserId.

| Action | Parameter | Efek |
|---|---|---|
| `RECEIVE` | @ItemId, @ToLocationId, @Qty>0, @Note | stocks += qty; movement RECEIVE |
| `ISSUE` | @ItemId, @FromLocationId, @Qty>0, @ResourceId wajib, @ProjectId null-able, @Note | **@ProjectId null → @Note wajib** (RAISERROR 'Isi project atau keterangan.'); stocks −= qty; movement ISSUE |
| `RETURN` | @ItemId, @WeightGram>0, @ToLocationId, @ResourceId (kembali dari), @ProjectId null-able | buat split cone baru (cone_code serial `SP-` + 6 digit, applock `thread_split_seq`), status IN_STOCK; movement RETURN dengan split_cone_id & weight. **Tidak ada kembali sebagai whole.** Mengembalikan `cone_code` + `thread_split_cone_id` |
| `ISSUE_SPLIT` | @SplitConeId, @ResourceId wajib, @ProjectId / @Note (aturan sama ISSUE) | status ISSUED, location null, issued_to/issued_project terisi; movement ISSUE_SPLIT (weight = berat saat ini) |
| `RETURN_SPLIT` | @SplitConeId, @WeightGram>0, @ToLocationId | status IN_STOCK, weight diperbarui, lokasi diisi; movement RETURN_SPLIT. Berat baru > berat lama → RAISERROR |
| `MOVE` | @ItemId, @FromLocationId, @ToLocationId, @Qty>0 | stocks dari −, ke +; movement MOVE |
| `MOVE_SPLIT` | @SplitConeId, @ToLocationId | ganti lokasi; movement MOVE_SPLIT |
| `EMPTY` | @SplitConeId, @Note | status EMPTY; movement EMPTY (dipakai kalau kones split dibuang) |

`ADJUST` / `ADJUST_SPLIT` **tidak** dibuat di prompt ini (Prompt 74).

### SP baca

- `inv.SIS_ThreadSplitCone_GetByCode` — hasil scan `TS:<cone_code>`; kembalikan cone + SKU.
- `inv.SIS_ThreadStock_ByItem` — stok per lokasi satu SKU (dipakai form Ambil/Pindah).
- `inv.SIS_ThreadMovement_Recent` — 20 movement terakhir satu SKU (untuk detail SKU).

Lookup line: `resources` aktif (nama + divisi) lewat SP lookup yang sudah ada kalau ada;
kalau tidak, `inv.SIS_ThreadLookup_Resources`. Lookup project: project aktif (manual_status
bukan COMPLETED/CANCELLED), tampilkan `project_name` + `no_po`.

## 2. API

Tambahkan ke `ThreadStockController`:
`POST movements/receive|issue|return|issue-split|return-split|move|move-split|empty`,
`GET scan/{code}` (parse prefix `TB:` → item, `TS:` → split cone; tanpa prefix → coba
sku_code lalu cone_code), `GET items/{id}/stocks`, `GET items/{id}/movements`,
`GET lookup/resources`, `GET lookup/projects`.

## 3. Client

**Baca dulu** `claude prompt/benang/mockup/Ambil.dc.html` dan `Kembali.dc.html`; form Ambil
dan Kembali mengikuti mockup itu persis (urutan field, radio lokasi dengan qty, stepper
qty, teks banner, ringkasan di tombol simpan). Form Terima dan Pindah dibuat dengan gaya
yang sama.

| Route | Isi | Mockup |
|---|---|---|
| `/gudang/benang/scan` | Kamera html5-qrcode (pola halaman Scan module TNI), kamera menyala terus. Hasil `TB:` → tampil kartu SKU + tombol **Ambil** / **Pindah** / **Kembali (timbang)**; `TS:` → kartu split cone + tombol **Ambil split** / **Timbang ulang** / **Pindah** / **Habis**. Kotak input manual untuk scanner Bluetooth (keyboard emulation): fokus otomatis, Enter = proses. | `Main.dc.html` (tombol scan) |
| `/gudang/benang/ambil/{itemId}` | Pilih lokasi (radio, tampil qty tiap rak), stepper qty, dropdown line (resources), dropdown project (+ opsi "— Tanpa project —"), keterangan (wajib kalau tanpa project — validasi client juga). Tombol simpan menampilkan ringkasan "Simpan · 6 kones dari A1". Setelah simpan → kembali ke scan dengan toast. | `Ambil.dc.html` |
| `/gudang/benang/kembali/{itemId}` | Input berat gram (font besar), dropdown "Kembali dari" (resource), project opsional, lokasi simpan. Banner: "Semua kones yang kembali dicatat sebagai split… Timbang tanpa tube." Tombol **Simpan** (cetak label menyusul Prompt 73 — sediakan tempat tombolnya). Setelah simpan tampilkan cone_code hasil. | `Kembali.dc.html` |
| `/gudang/benang/kembali/split/{splitId}` | Timbang ulang split yang kembali dari line. | — |
| `/gudang/benang/terima` | Pilih SKU (SearchableSelect atau scan), qty, lokasi. Boleh input beberapa baris lalu simpan sekaligus (loop panggil RECEIVE per baris, satu transaksi tidak perlu). | — |
| `/gudang/benang/pindah/{itemId}` | Dari rak → ke rak, qty. | — |

Landing (Prompt 71): aktifkan tombol Scan / Ambil / Kembali; tombol Ambil tanpa SKU membuka
scan. Detail SKU: tambah tab "Riwayat" (20 terakhir) dan tombol Ambil / Pindah per lokasi.

## 4. Verifikasi

Build; jalankan skenario di `sql/inv/test_72_movement.sql` (script T-SQL yang memanggil SP
dengan data uji lalu SELECT saldo, dibungkus transaksi + ROLLBACK di akhir): RECEIVE 10 →
ISSUE 6 (tanpa project tanpa note harus gagal) → RETURN 420 g → ISSUE_SPLIT → RETURN_SPLIT
300 g → MOVE 2 → saldo akhir benar.

## Yang TIDAK boleh dilakukan

- Jangan buat ADJUST (Prompt 74). Jangan buat print job (Prompt 73).
- Jangan ubah tabel `resources`, `projects`.
