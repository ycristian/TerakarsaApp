# Fix 01 — Foto Hilang di Disk Menyebabkan 500 & Crash Halaman

## Latar Belakang Bug

Endpoint `GET /api/article-photos/by-project/{projectId}/first-photo` mengembalikan **500 Internal Server Error** ketika record foto ada di DB tetapi file fisiknya tidak ada di disk. Karena exception tidak tertangani, response 500 keluar tanpa header CORS sehingga browser memblokirnya. Akibatnya `HttpClient` di Blazor client melempar `HttpRequestException` ("Failed to fetch") yang tidak tertangkap, dan **seluruh halaman Project crash saat render** (unhandled exception di `OnInitializedAsync`).

Kasus 404 (project tanpa foto) sudah benar dan tidak perlu diubah.

## Tujuan

1. File hilang di disk = perlakukan sama seperti foto tidak ada → **404**, bukan 500.
2. Kegagalan fetch satu thumbnail di client **tidak boleh** menjatuhkan halaman.

## Perubahan yang Diminta

### 1. API — `TerakarsaApp.API/Services/ArticlePhotoService.cs`

Di **semua** method yang membuka file fisik untuk download/stream (minimal: `GetFirstPhotoForProjectAsync` / method first-photo per project, `GetPrimaryPhotoForDownloadAsync`, `GetFileForDownloadAsync`):

- Sebelum membuka stream, cek keberadaan file fisik. Gunakan mekanisme yang konsisten dengan `IFileStorageService` yang ada — jika interface belum punya method cek keberadaan file, tambahkan `bool FileExists(string filePath)` (atau `Task<bool> FileExistsAsync`) dan implementasikan di implementasi lokalnya.
- Jika file tidak ada → return `null` sehingga controller mengembalikan `NotFound()`.
- Jangan ubah perilaku ketika record DB memang tidak ada (tetap null → 404).

### 2. API — `TerakarsaApp.API/Services/ProjectAttachmentService.cs`

Terapkan guard yang sama pada `GetFirstPhotoForDownloadAsync` dan `GetFileForDownloadAsync` (bug yang sama berpotensi terjadi di lampiran project).

### 3. Client — `TerakarsaApp.Client/Services/ArticlePhotoApiService.cs`

Bungkus body method berikut dengan `try/catch (HttpRequestException)` yang mengembalikan `null` (atau list kosong sesuai return type):

- `GetFirstPhotoForProjectAsync`
- `GetPrimaryPhotoAsync`
- `DownloadAsync`
- `GetByArticleAsync`

Jangan menampilkan error ke user untuk kegagalan thumbnail — cukup gagal diam-diam (thumbnail tidak tampil).

### 4. Client — `TerakarsaApp.Client/Services/ProjectAttachmentApiService.cs`

Guard yang sama untuk `GetFirstPhotoAsync`, `DownloadAsync`, dan `GetByProjectAsync`.

### 5. Client — `TerakarsaApp.Client/Pages/Project.razor`

Di `LoadThumbnails`, pastikan kegagalan load thumbnail satu project tidak menghentikan project lain dan tidak melempar exception ke renderer:

- Bungkus pemanggilan per-project dengan try/catch, atau andalkan service yang kini sudah return null.
- Project tanpa thumbnail cukup menampilkan placeholder yang sudah ada.

Lakukan hal yang sama pada halaman lain yang memuat preview foto jika polanya sama (`ProjectEdit.razor` `LoadPhotoPreviews`, `ArticleEdit.razor` `LoadPhotoPreviews`).

## Batasan

- Jangan mengubah kontrak endpoint (route, DTO, status code selain 500→404 untuk kasus file hilang).
- Jangan menambah kolom DB atau SP baru — ini murni perbaikan di layer service/client.
- Jangan menghapus record DB yang file-nya hilang (bukan scope prompt ini).
- UI tetap berbahasa Indonesia; tidak ada perubahan UI selain memastikan placeholder tampil.

## Verifikasi

1. Build solution sukses tanpa warning baru.
2. Simulasi: hapus/rename file fisik salah satu foto yang ada record DB-nya → endpoint first-photo mengembalikan **404** (bukan 500), halaman Project tetap render normal dengan placeholder.
3. Project tanpa foto → tetap 404, tidak ada regresi.
4. Project dengan foto valid → thumbnail tetap tampil normal.
