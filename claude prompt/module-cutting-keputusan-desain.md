# Module Stok Bundle Cutting — Keputusan Desain

Disepakati 15 Okt 2026. Dasar untuk Prompt 78–80. Mockup referensi: kanvas "Mockup Admin Cutting" (4 layar tablet) → disimpan ke `claude prompt/cutting/mockup/`.

---

## 1. Tujuan

Cutting membentuk bundle di sistem sejak kain dihampar, mencetak stiker bundle, dan bundle masuk **stok cutting**. Bundling tinggal **mengambil** bundle dengan scan — bukan membuat bundle lagi. Dipakai **Admin Cutting lewat tablet** (login akun, bukan station).

## 2. Istilah lapangan

| Istilah | Artinya |
|---|---|
| Hamparan | Satu kali hampar kain. Identitas: **kode hamparan** (`H01`, `H02`, … urut per artikel, boleh diganti manual). Tidak ada istilah lot. |
| Set | Satu tumpukan pola dalam hamparan. Hamparan = N set × M lembar (mis. 12 × 220 = 2.640 pcs). |
| Rincian size | Set dibagi per size (mis. 6 set M, 6 set L). Satu set = satu size. |
| Numbering | Nomor pcs per artikel per size, manual pakai mesin numbering. Sistem hanya **menentukan rentang**, lanjut dari hamparan terakhir artikel itu (M-1…M-1320 → hamparan berikut mulai M-1321). |
| Bundle | Potongan dari **satu set** (tidak lintas set). Target ~50 pcs, diatur per artikel. |

## 3. Aturan pembagian bundle (saran sistem)

- `n = round(lembar ÷ target)`, minimal 1 → bagi rata; sisa pembagian ditaruh di bundle pertama.
- Batas maksimal per bundle = `target + 10`. Kalau hasil bagi rata melewati batas → `n + 1`.
- Contoh target 50: 220 → 55·55·55·55; 249 → 50·50·50·50·49; 230 → 46×5; 260 → 52×5; 225 → 45×5.
- Saran hanya saran: Admin Cutting boleh ubah qty per bundle dan tambah/kurang bundle. Validasi: total per set harus = lembar. Set yang belum pas ditandai dan tombol cetak terkunci.
- `bundle_target_qty` disimpan di `articles` (default 50).

## 4. Kode & QR

- **Kode bundle** = `<kode hamparan>-<size>-<urut 2 digit>`, urut per hamparan per size (set 1 = 01–04, set 2 = 05–08, …). Contoh `H06-M-03`.
- Kode ini **tidak unik lintas artikel**. Yang unik = id bundle. **QR berisi id bundle** (ikut format QR bundle yang sudah dipakai sistem bila ada); kode bundle dicetak sebagai teks.
- Rentang nomor pcs (M-111 s/d M-165) **tidak** masuk kode, hanya dicetak di stiker.

## 5. Stiker bundle

- Dicetak lewat **antrian print job TSC** seperti stiker penyerahan bundle, ukuran label mengikuti yang sudah dipakai di sana.
- Isi: kode bundle (besar), PO · artikel, size, qty, set ke-, rentang nomor, kode hamparan + tanggal, **QR**.
- Dicetak langsung saat hamparan disimpan ("Simpan & cetak N stiker"). Bisa cetak ulang per bundle atau semua.

## 6. Status & kunci

- Bundle hasil cutting masuk tabel `bundles` yang ada, dengan penanda `source = CUTTING` dan status stok `STOCK` → `TAKEN`.
- **Pengambilan**: Station Bundling scan QR → status `TAKEN`, dicatat line/station + waktu, lalu masuk alur workflow yang sudah ada (log Cutting → Bundling seperti penerimaan bundle sekarang).
- Sebelum diambil: Admin Cutting boleh edit qty bundle (menggeser rentang nomor bundle setelahnya di set yang sama, bundle yang berubah ditandai perlu cetak ulang), hapus hamparan yang belum ada bundle terambil.
- Setelah diambil: cutting tidak bisa edit/hapus bundle itu. Koreksi lewat jalur admin/superadmin seperti biasa.
- Cara buat bundle lama (manual oleh admin) **tetap ada** untuk artikel yang tidak lewat module ini.

## 7. Stok bundle

- Tampilan **global per artikel per size**: total bundle, tersedia (STOCK), diambil (TAKEN), pcs tersedia. Tidak perlu per hamparan.
- Ringkasan atas: bundle & pcs di stok cutting, diambil hari ini, hamparan belum dicetak.

## 8. Akses & UI

- Module `CUTTING` — role baru **Admin Cutting**, hanya module ini, landing sendiri `/cutting` (pola Admin Gudang). Owner tetap bisa masuk.
- Layar tablet landscape (~1024px); tetap bisa dibuka di HP (satu kolom).
- Halaman: Stok Bundle (landing) · Buat Hamparan · Daftar & Detail Hamparan.
- Station Bundling: tambahan aksi **Scan Stok Bundle** (kamera HP/tablet).
- App Android "Terakarsa": pilihan tujuan setelah login bertambah **Admin Cutting** (muncul kalau user punya module `CUTTING`).

## 9. Prompt 78–80

| Prompt | Isi |
|---|---|
| 78 | Schema: `spreads`, `spread_sizes`, kolom baru di `bundles` & `articles`; SP manage + read; module `CUTTING` + role Admin Cutting + landing + halaman Stok Bundle |
| 79 | Buat Hamparan: form, numbering lanjut, saran bundle (algoritma §3), edit qty, simpan → bundle + print job stiker QR; Daftar & Detail Hamparan: status, edit, cetak ulang, hapus draft |
| 80 | Station Bundling: Scan Stok Bundle → TAKEN + log workflow; kunci edit cutting setelah TAKEN; bundle manual tetap jalan; App Android: tambah tujuan Admin Cutting |

Eksekusi DDL: Claude Code langsung ke database (seperti seri TNI & benang).
