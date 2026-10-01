-- Prompt 57: Registrasi module UNLOCK_REQUEST -- meja admin untuk memeriksa & memutuskan
-- pengajuan buka lock dari stasiun (SIS_UnlockRequest_Manage APPROVE/REJECT, Prompt 55).
-- Category "Sistem" bersama SUPER_ADMIN -- keduanya membuka kembali data yang sudah beku,
-- jadi ditaruh di grup menu yang sama dan sama-sama di bawah.
-- SENGAJA TIDAK auto-assign ke role/user mana pun (pola sama dengan SUPER_ADMIN): menyetujui
-- unlock = membolehkan angka periode gajian diubah lagi, jadi akses HARUS diberikan manual
-- lewat halaman Module Access, satu user per satu.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'UNLOCK_REQUEST')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('UNLOCK_REQUEST', 'Request Unlock', 'Sistem', NULL, 'unlock-requests', 'fe fe-unlock', 890, 1, GETDATE());
GO
