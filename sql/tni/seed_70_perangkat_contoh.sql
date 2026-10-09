-- Data awal perangkat PDH TNI AD (2026-10-02, disesuaikan alter_75 2026-10-06).
--
-- Satu perangkat contoh supaya alur pairing bisa langsung diuji. Sejak alter_75
-- setiap perangkat punya SATU nama petugas (kolom nama_petugas) -- tidak ada
-- lagi tabel petugas. Ubah/hapus lewat halaman /tni/perangkat.
--
-- KODE PAIRING TIDAK diseed: masa berlakunya hanya 15 menit, jadi harus dibuat
-- dari halaman /tni/perangkat tepat sebelum dipakai.
-- Idempotent: aman dijalankan berulang.

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Username = 'tni_system');

IF @U IS NULL
BEGIN
    RAISERROR('User tni_system belum ada -- jalankan sql/tni/seed_70_tni_system_user.sql dulu.', 16, 1);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM tni.perangkat WHERE perangkat_code = 'TAB01' AND deleted_at IS NULL)
    EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE', @PerangkatCode = 'TAB01',
        @PerangkatName = 'Tablet Lantai 1', @NamaPetugas = 'Petugas 1',
        @Keterangan = 'Perangkat contoh -- ubah sesuai kebutuhan',
        @UserId = @U;
GO

SELECT perangkat_code AS Perangkat, perangkat_name AS Nama, nama_petugas AS Petugas, is_active AS Aktif
FROM tni.perangkat WHERE deleted_at IS NULL ORDER BY perangkat_code;
GO
