-- Prompt 83: registrasi dua module admin.
--   MANUAL_OUTPUT  -- daftar semua output manual + aksi "Hubungkan ke Artikel" massal.
--   PAYROLL_REKAP  -- Rekap Gajian: baris LOG + MANUAL per resource, koreksi harga
--                     (SIS_LockItem_UpdatePrice) dan tombol Finalisasi Periode.
--
-- SENGAJA TIDAK auto-assign ke role/user mana pun (pola sama dengan UNLOCK_REQUEST &
-- SUPER_ADMIN): PAYROLL_REKAP memegang nominal upah dan tombol yang membekukannya, jadi
-- akses HARUS diberikan manual lewat halaman Module Access, satu user per satu.
-- MANUAL_OUTPUT ikut aturan yang sama -- menempelkan artikel ke baris yang sudah lock
-- bisa mengubah harga yang dibekukan (lewat pengisian unit_price yang masih NULL).
--
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

-- Category 'Order' mengikuti REPORT_BUNDLE (53) / REPORT_PRODUKSI (55) / REPORT_ACTIVITY (56)
-- -- grup menu yang sama dengan laporan produksi lain.
IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MANUAL_OUTPUT')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MANUAL_OUTPUT', 'Output Manual', 'Order', NULL, 'manual-outputs', 'fe fe-edit-3', 57, 1, GETDATE());
GO

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'PAYROLL_REKAP')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('PAYROLL_REKAP', 'Rekap Gajian', 'Order', NULL, 'payroll-rekap', 'fe fe-dollar-sign', 58, 1, GETDATE());
GO
