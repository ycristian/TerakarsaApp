# Prompt 11e — Aturan UX Navigasi: Tombol Close & Konsolidasi Halaman Edit Bundle

## Konteks

Aturan UX baru: setiap halaman turunan (edit article, edit bundle, dst.) adalah halaman penuh terpisah dengan tombol **Close** yang kembali ke halaman asal. Halaman kelola/edit bundle dipindah jadi route milik bundle sendiri dan hanya ada di SATU tempat — semua pintu (Edit Article, halaman /bundles) menavigasi ke sana. Tidak ada perubahan SP, API, atau logika bisnis — murni client (Blazor).

## 1. Komponen reusable `CloseButton.razor`

Buat di `TerakarsaApp.Client/Shared/`:

- Tampilan: tombol dengan icon close (mis. `fe fe-x`) + teks "Tutup", diletakkan pemanggil di area header halaman.
- Parameter: `FallbackUrl` (string, wajib).
- Perilaku klik: panggil `history.back()` via `IJSRuntime` (pola JS interop yang sudah ada). Kalau tidak ada riwayat (halaman dibuka langsung dari URL / `history.length <= 1`) → `NavigationManager.NavigateTo(FallbackUrl)`.
- Cara deteksi paling sederhana yang andal: JS function kecil yang mengembalikan `window.history.length > 1`; kalau true → `history.back()`, kalau false → fallback. Tambahkan function ini ke file JS interop yang sudah ada (jangan buat file JS baru kalau sudah ada tempatnya).

Aturan ke depan (tulis sebagai komentar di komponen): semua halaman turunan WAJIB memakai `CloseButton`, bukan tombol "Kembali ke X" buatan sendiri.

## 2. Halaman Edit Bundle pindah ke `/bundles/{articleId}/edit`

- Ganti route `TerakarsaApp.Client/Pages/Bundle.razor` dari `/articles/{ArticleId:int}/bundles` menjadi `/bundles/{ArticleId:int}/edit`. Judul halaman: "Edit Bundle".
- Hapus tombol "Kembali ke Edit Artikel" → ganti `CloseButton` dengan `FallbackUrl="/bundles"`.
- `BundleManager.razor` tetap dipakai di halaman ini, jangan diubah isinya.
- Route lama `/articles/{articleId}/bundles` dihapus. Cari seluruh referensi route lama di client dan arahkan ke route baru.

## 3. Halaman `/bundles` (BundlePicker) — hapus panel inline

- Panel inline `BundleManager` di `/bundles` DIHAPUS. Setelah user memilih artikel (dari tabel per project maupun hasil pencarian lintas project), aksi per artikel adalah tombol **"Kelola"** → `NavigateTo("/bundles/{articleId}/edit")`.
- Bagian pemilih (dropdown project → tabel artikel, kotak pencarian lintas project) tetap seperti sekarang.
- Kalau setelah ini `BundleManager` hanya dipakai di satu tempat, biarkan tetap sebagai komponen (jangan di-inline balik ke page).

## 4. Halaman Edit Article

- Route tidak berubah (`/projects/{projectId}/articles/{articleId}/edit`).
- Ganti tombol "Kembali ke Edit Project" → `CloseButton` dengan `FallbackUrl="/projects/{projectId}/edit"` (sesuaikan dengan route edit project yang sebenarnya).
- Tombol "Kelola Bundle" tetap ada (dengan cek module BUNDLE_MANAGE yang sudah berlaku), targetnya diganti ke `/bundles/{articleId}/edit`.

## 5. Halaman Edit Project

- Ganti tombol kembali/batal yang menavigasi ke list project → `CloseButton` dengan `FallbackUrl="/projects"`.
- Kalau ada tombol "Batal" pada form yang fungsinya sama dengan kembali, samakan perilakunya (boleh tetap bertuliskan "Batal" tapi memakai logika CloseButton, atau hapus salah satunya — jangan ada dua tombol dengan tujuan sama).

## Aturan tetap berlaku

UI bahasa Indonesia. Jangan sentuh SP, API, controller, atau tabel apa pun.

## Yang TIDAK boleh dilakukan

- Jangan ubah `BundleManager.razor` selain hal yang diminta.
- Jangan ubah otorisasi/module (BUNDLE_MANAGE tetap).
- Jangan buat menu sidebar baru.
- Jangan ubah halaman `/station`.

Setelah selesai: daftar file yang dibuat/diubah. Tidak ada script SQL di prompt ini.
