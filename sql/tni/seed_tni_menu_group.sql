-- Mengelompokkan SEMUA module PDH TNI AD jadi satu menu induk "TNI Siliwangi" yang bisa
-- dibuka/ditutup, bukan beberapa item lepas di grup Order.
--
-- Caranya murni DATA: NavMenu.razor sudah merender setiap SubCategory sebagai menu induk
-- (data-bs-toggle="slide" + chevron) dengan anak-anaknya di dalam -- mekanisme yang sama
-- dipakai Setting -> Master Data. Jadi tidak ada kode yang perlu diubah; cukup isi
-- Modules.SubCategory.
--
-- Hasil di sidebar:
--   ORDER
--     ...
--     TNI Siliwangi  >        <- menu induk, klik untuk buka
--         PDH TNI AD
--         Persetujuan PDH TNI
--         Perangkat PDH TNI
--     ...
--
-- SENGAJA tetap di Category 'Order': Category dirender sebagai JUDUL SEKSI (teks mati), bukan
-- menu yang bisa diklik, jadi memindahkan TNI ke Category sendiri justru menghilangkan "menu
-- induk" yang diminta.
--
-- Idempotent: hanya menyentuh baris yang SubCategory-nya belum benar. Tidak membuat module
-- baru, tidak menyentuh UserModules, tidak mengubah Route/Icon/akses.

DECLARE @SubCat NVARCHAR(100) = N'TNI Siliwangi';

UPDATE Modules
SET SubCategory = @SubCat
WHERE Code IN ('TNI_PDH', 'TNI_PDH_APPROVE', 'TNI_PDH_PERANGKAT')
  AND ISNULL(SubCategory, N'') <> @SubCat;
GO

-- SortOrder di dalam grup menentukan urutan anak, dan nilai TERKECIL di grup itu juga
-- menentukan posisi menu induknya di antara item lain (lihat SubGroupEntry di NavMenu.razor).
-- Urutan yang diinginkan: kiosk dulu, lalu dua halaman admin.
UPDATE Modules SET SortOrder = 57 WHERE Code = 'TNI_PDH'           AND SortOrder <> 57;
UPDATE Modules SET SortOrder = 58 WHERE Code = 'TNI_PDH_APPROVE'   AND SortOrder <> 58;
UPDATE Modules SET SortOrder = 59 WHERE Code = 'TNI_PDH_PERANGKAT' AND SortOrder <> 59;
GO

SELECT Code, Name, Category, SubCategory, Route, Icon, SortOrder
FROM Modules
WHERE SubCategory = N'TNI Siliwangi'
ORDER BY SortOrder;
GO
