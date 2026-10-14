# Prompt 74 — Stok Benang: Stock Opname, Rekonsiliasi, ADJUST dengan Alasan

Dijalankan SETELAH Prompt 73.

## Prinsip (dari dokumen keputusan)

Stok sistem dan hasil opname disimpan terpisah. Opname **tidak** mengubah stok; yang
mengubah stok hanya movement `ADJUST` / `MOVE` yang dibuat saat sesi ditutup, masing-masing
menunjuk baris opname-nya dan membawa alasan.

## 1. Tabel — `sql/inv/create_74_inv_thread_opname.sql`

```sql
inv.thread_opname_sessions (thread_opname_session_id PK, session_no varchar(20) UQ 'SO26-0001',
                            status varchar(10) CHECK IN ('OPEN','CLOSED'),
                            started_at, closed_at null, closed_by null, note)
inv.thread_opname_locations (id PK, session_id FK, thread_location_id FK,
                            status varchar(10) CHECK IN ('PENDING','DRAFT','DONE'),
                            UQ (session_id, thread_location_id))
inv.thread_opname_lines    (thread_opname_line_id PK, session_id FK, thread_location_id FK, thread_item_id FK,
                            system_qty int not null,      -- snapshot saat baris dibuat/dihitung
                            counted_qty int null,         -- null = belum dihitung
                            counted_at datetime2 null, counted_by int null,
                            split_expected int not null default 0,
                            split_found int null,
                            resolution varchar(10) null CHECK IN ('MOVE','ADJUST','NONE'),
                            resolved_movement_id FK thread_movements null,
                            UQ (session_id, thread_location_id, thread_item_id))
inv.thread_opname_splits   (id PK, line_id FK, thread_split_cone_id FK, is_found bit null,
                            UQ (line_id, thread_split_cone_id))
```

Tambahkan FK `thread_movements.opname_line_id → thread_opname_lines`.

## 2. SP — `sql/inv/sp_74_ThreadOpname.sql`

### `inv.SIS_ThreadOpname_Manage` (@Action)

| Action | Isi |
|---|---|
| `OPEN` | @LocationIdsJson (array int; kosong = semua lokasi aktif). Tolak kalau masih ada sesi OPEN. Buat session + satu baris `opname_locations` per rak + **baris `opname_lines` untuk setiap SKU yang punya `thread_stocks.qty_whole > 0` atau split IN_STOCK di rak itu**, `system_qty` = saldo saat ini, `split_expected` = jumlah split IN_STOCK, dan `opname_splits` per cone. |
| `ADD_LINE` | @SessionId, @LocationId, @ItemId — untuk SKU yang ditemukan fisik tapi sistem 0 di rak itu (hasil scan). `system_qty` = saldo saat itu (biasanya 0). |
| `COUNT` | @LineId, @CountedQty, @SplitFoundJson ([{split_cone_id, is_found}]) → isi counted_*, status rak → DRAFT |
| `LOCATION_DONE` | @SessionId, @LocationId → semua baris rak itu harus `counted_qty IS NOT NULL`; status DONE |
| `PREVIEW_CLOSE` | lihat §3; hanya SELECT, tidak menulis |
| `CLOSE` | @SessionId, @ResolutionsJson (lihat §3) → buat movement, isi `resolution`/`resolved_movement_id`, session CLOSED. Satu transaksi. |
| `CANCEL` | hapus (soft) sesi OPEN tanpa movement |

Baris yang `counted_qty IS NULL` saat CLOSE → RAISERROR 'Masih ada %d SKU belum dihitung.'

### Rekonsiliasi (`PREVIEW_CLOSE`)

Per SKU dalam sesi, hitung `diff = counted − system` tiap rak.

1. **Usulan MOVE**: pasangkan rak minus dengan rak plus untuk SKU yang sama, greedy, sampai
   salah satu habis. Tiap pasangan = usulan `MOVE` qty = min(|minus|, plus).
2. Sisa diff per rak = usulan `ADJUST` (+ atau −), **alasan wajib**.
3. Split: cone `is_found = 0` → usulan `ADJUST_SPLIT` (set EMPTY, alasan wajib). Cone
   IN_STOCK ditemukan di rak lain (di-scan saat opname rak lain) → `MOVE_SPLIT`.

Hasil preview = daftar usulan dengan `proposal_id` sementara. Client menampilkan, admin
boleh mengubah: menolak usulan MOVE (jadi dua ADJUST), memilih `reason_code`, mengisi
`note`. `CLOSE` menerima `@ResolutionsJson`:
`[{line_id, action:'MOVE'|'ADJUST'|'NONE', qty, from_location_id, to_location_id, reason_code, note}]`
dan **memvalidasi ulang** di SP: `reason_code` wajib untuk ADJUST (`requires_note` → note
wajib), qty MOVE tidak melebihi minus, hasil akhir per rak harus sama dengan `counted_qty`.

### SP baca

`inv.SIS_ThreadOpname_Current` (sesi OPEN + daftar rak + progres), `inv.SIS_ThreadOpname_Lines`
(@SessionId, @LocationId → baris + split), `inv.SIS_ThreadOpname_List` (riwayat sesi),
`inv.SIS_ThreadOpname_GetById` (sesi tertutup: baris + resolusi + movement).

### `inv.SIS_ThreadMovement_Manage` — tambah action

`ADJUST` (@ItemId, @LocationId, @Qty ±, @ReasonCode wajib, @Note, @OpnameLineId wajib) dan
`ADJUST_SPLIT` (@SplitConeId → EMPTY, @ReasonCode, @Note, @OpnameLineId). **ADJUST hanya
boleh lahir dari opname** — tanpa `@OpnameLineId` → RAISERROR. Tidak ada halaman adjust
manual.

## 3. Client

**Baca dulu** `claude prompt/benang/mockup/Opname.dc.html` (HP) dan `TabletOpname.dc.html`
(tablet). Ikuti: progres "Sudah dihitung 3 dari 7 SKU", input fisik berwarna (cocok hijau,
selisih oranye), baris belum dihitung pudar bergaris putus, kolom split "n kones · ada m",
tombol Simpan draft / Selesaikan rak di bawah, dan di tablet daftar rak dengan status di
panel kiri.

| Route | Isi | Mockup |
|---|---|---|
| `/gudang/benang/opname` | Kalau tidak ada sesi OPEN: tombol **Mulai opname** → pilih rak (checkbox, default semua). Kalau ada: daftar rak dengan progres (3/7, selesai), tombol lanjut per rak, tombol **Tutup sesi**. Tablet: rak di kiri, tabel rak terpilih di kanan. | `Opname.dc.html`, `TabletOpname.dc.html` |
| `/gudang/benang/opname/{sessionId}/rak/{locationId}` | Tombol **Scan SKU berikutnya** (scan `TB:` → lompat/sorot baris; SKU tak ada di rak → tawarkan ADD_LINE). Baris: foto, nama·kode, sistem, input fisik (besar, autofocus berikutnya), selisih berwarna (cocok hijau / selisih oranye), split: "n kones · ada m" + expand checklist per cone. Tombol **Simpan draft** / **Selesaikan rak**. | sama |
| `/gudang/benang/opname/{sessionId}/tutup` | Preview rekonsiliasi: kelompok per SKU → usulan MOVE (bisa ditolak) dan ADJUST (dropdown alasan, keterangan). Ringkasan: n MOVE, n ADJUST+, n ADJUST−, n split habis. Tombol **Posting & tutup sesi** + modal konfirmasi. | — |
| `/gudang/benang/opname/riwayat` + `/{id}` | Sesi tertutup: baris, selisih, resolusi, alasan, siapa. | — |

Landing: kartu kecil "Opname berjalan · 3/7 rak" kalau ada sesi OPEN.

## 4. Stok awal

Tidak ada fitur khusus: owner membuat lokasi + SKU, lalu buka opname pertama (sistem 0),
hitung, tutup dengan alasan `STOK_AWAL`. Pastikan `ADD_LINE` dan alur ini lancar — ini
cara data awal masuk.

## 5. Verifikasi

`sql/inv/test_74_opname.sql` (transaksi + ROLLBACK): stok A1=20, B5=8 → opname A1 fisik 18,
B5 fisik 10 → PREVIEW mengusulkan MOVE A1→B5 2 tanpa ADJUST; variasi A1 18, B5 8 → ADJUST −2
wajib alasan, CLOSE tanpa reason harus gagal.

## Yang TIDAK boleh dilakukan

- Opname tidak boleh menulis `thread_stocks` secara langsung — hanya lewat
  `SIS_ThreadMovement_Manage`.
- Jangan buat halaman adjust manual.
