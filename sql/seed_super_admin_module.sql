-- Prompt 29: Registrasi module Super Admin (koreksi langsung bundle & workflow log,
-- bypass guard normal). Category "Sistem" tersendiri, SortOrder tinggi supaya selalu
-- tampil di grup menu paling bawah.
-- SENGAJA TIDAK auto-assign ke role/user mana pun (beda dengan module lain) -- fitur ini
-- melewati guard normal dan hanya boleh dipakai user terpilih. Pemberian akses HARUS lewat
-- halaman manajemen user (Module Access) secara manual, satu per satu.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'SUPER_ADMIN')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('SUPER_ADMIN', 'Super Admin', 'Sistem', NULL, 'super-admin', 'fe fe-shield', 900, 1, GETDATE());
GO
