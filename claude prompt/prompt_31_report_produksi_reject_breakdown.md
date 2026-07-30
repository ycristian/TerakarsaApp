# Prompt 31 — Breakdown Reject di Laporan Produksi

## Konteks
Laporan Produksi (Prompt 30, `/reports/produksi`) menampilkan kolom **Reject** tunggal, sengaja hanya `qty_reject_print + qty_reject_fabric + qty_reject_sewing` (3 kategori, TIDAK termasuk rework/lost — lihat header `sql/sp_Report_Produksi.sql`). User minta breakdown lebih detail: Reject Fabric, Reject Sewing, Hilang, dll.

Disepakati lewat konfirmasi user:
- Pecah **semua 5 kategori**: Reject Print, Reject Fabric, Reject Sewing, Reject Rework, Hilang (`qty_lost`) — sama dengan `sp_Article_Wip.sql` yang sudah pakai 5 kategori.
- Tampil di **tabel Agg (tab Semua) dan Detail (tab per-Pelaksana + modal drill-down bundle)**, kolom **Reject total dipertahankan** (sekarang = SUM kelima kategori, bukan lagi 3) dengan kolom breakdown ditambahkan di sebelahnya.
- Summary card atas halaman TIDAK diubah (tetap satu angka Reject total).

**Revisi definisi (menggantikan Prompt 30):** Reject = SUM 5 kategori, bukan 3. Konsekuensi: total Reject di laporan ini sekarang bisa lebih besar dari sebelumnya untuk data yang sama (kalau ada baris `qty_reject_rework`/`qty_lost` > 0). WIP `Tercatat` (formula `qty_ok + reject`) ikut diperluas ke 5 kategori juga supaya konsisten — bundle/size yang qty_lost/rework-nya sudah dicatat tidak lagi dihitung nyangkut WIP selamanya.

## 1. SQL — `sql/sp_Report_Produksi.sql`
- `DirectAtoms` (Agg & Detail): pecah case reject jadi 5 kolom (`QtyRejectPrint/Fabric/Sewing/Rework`, `QtyLost`), timing sama seperti sebelumnya (per kategori, bukan cuma total).
- `BundleTercatat`/`SizeTercatat`: formula `qty_ok + 5 kategori` (tambah `qty_reject_rework + qty_lost`).
- `BundleWip`/`SizeWip`: breakdown kategori = 0 (baris WIP sintetis, bukan reject nyata).
- SELECT akhir Agg & Detail: tambah `SUM` per kategori + `QtyReject` = SUM kelimanya. HAVING ikut disesuaikan.

## 2. Shared — `TerakarsaApp.Shared/Reports/ReportProduksiModels.cs`
Tambah `QtyRejectPrint`, `QtyRejectFabric`, `QtyRejectSewing`, `QtyRejectRework`, `QtyLost` (int) ke `ProduksiAggRowDto` dan `ProduksiDetailRowDto`. `ProduksiSummaryDto` TIDAK diubah.

## 3. Client — `TerakarsaApp.Client/Pages/ReportProduksi.razor`
- Tabel tab Semua, tabel tab Pelaksana, dan modal drill-down bundle: tambah kolom Print/Fabric/Sewing/Rework/Hilang setelah kolom Reject (termasuk baris TOTAL).
- `ArticleSummaryRow` + `ArticleSummaryFor`: ikut agregasi 5 kolom baru.
- Export CSV (`BuildAggCsv`, `BuildArticleSummaryCsv`): tambah 5 kolom baru di header + tiap baris + total.

## Kriteria selesai
- Build hijau.
- Kolom Reject total = penjumlahan 5 kolom breakdown di baris yang sama, konsisten di semua tabel (Agg, Detail, modal, TOTAL row).
- Angka reconcile antara tab Semua dan penjumlahan seluruh tab Pelaksana (sama seperti sebelumnya).
