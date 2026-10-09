-- Prompt 70 -- Seed jabatan "Satpam" dengan is_gate_operator = 1.
-- Idempotent: hanya membuat kalau belum ada baris hidup bernama 'Satpam'; kalau sudah ada,
-- flag gate-operator-nya dipastikan 1 tanpa menyentuh apa pun yang lain.
-- Jalankan SETELAH alter_70_absensi_rfid.sql (butuh kolom positions.is_gate_operator).
--
-- Kenapa jabatan ini perlu di-seed: kartu PERTAMA mustahil didaftarkan dari perangkat gate,
-- karena menu satpam baru terbuka setelah ada kartu dengan jabatan is_gate_operator = 1.
-- Jadi jabatan ini harus ada lebih dulu, lalu kartu pertama didaftarkan dari halaman admin
-- /attendance (tab Kartu Karyawan, mode tap).
--
-- SENGAJA TIDAK memetakan ke division_positions: pemetaan kosong berarti jabatan ini muncul di
-- dropdown SEMUA divisi (aturan fallback SIS_Position_GetByDivision, Prompt 58). Satpam tidak
-- melekat ke satu divisi produksi mana pun, jadi itu memang perilaku yang diinginkan.

DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

IF NOT EXISTS (SELECT 1 FROM positions WHERE position_name = 'Satpam' AND deleted_at IS NULL)
BEGIN
    INSERT INTO positions (position_name, is_gate_operator, created_at, created_by)
    VALUES ('Satpam', 1, SYSDATETIME(), @AdminUserId);
END
ELSE
BEGIN
    -- Jabatannya sudah ada (mis. dibuat manual lewat UI sebelum script ini dijalankan):
    -- cukup pastikan flag gate-operator-nya nyala.
    UPDATE positions
    SET is_gate_operator = 1,
        updated_at = SYSDATETIME(),
        updated_by = @AdminUserId
    WHERE position_name = 'Satpam' AND deleted_at IS NULL AND is_gate_operator = 0;
END
GO

SELECT position_id, position_name, is_gate_operator
FROM positions
WHERE deleted_at IS NULL AND is_gate_operator = 1;
GO
