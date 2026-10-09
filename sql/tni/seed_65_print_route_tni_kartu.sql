-- Routing job cetak kartu personel PDH TNI AD (Prompt 65).
--
-- Kartu personel dicetak ke printer THERMAL 80mm yang SUDAH ADA
-- (print_devices.device_code = 'THERMAL', Iware XS-80BT, Font A 48 kolom) --
-- printer yang sama dengan struk/kupon. TIDAK ada printer baru yang didaftarkan,
-- dan render_mode print_devices TIDAK disentuh.
--
-- CATATAN PENTING soal render:
--   job_type TNI_KARTU dirakit di C# (TniKartuEscPosBuilder di PrintService),
--   BUKAN lewat token SP seperti job_type kupon. Worker menangkapnya berdasarkan
--   job_type SEBELUM switch RenderMode, jadi nilai render_mode device ini
--   ('TOKEN', dipakai kupon) tidak berpengaruh untuk TNI_KARTU.
--   Karena itu TNI_KARTU juga TIDAK didaftarkan di print_kupon_job_types.
--
-- Kalau nanti kartu mau dipindah ke printer 80mm lain, cukup:
--   UPDATE print_job_routes SET print_device_id = <id printer baru>
--   WHERE job_type = 'TNI_KARTU' AND deleted_at IS NULL;
-- Berlaku langsung untuk job yang masih PENDING, tanpa restart service.
--
-- Ini satu-satunya baris dbo yang disentuh seri 60-69 selain seed
-- Modules/UserModules. Idempotent.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @SeedUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
IF @SeedUserId IS NULL BEGIN RAISERROR('Tidak ada user Admin untuk created_by seed.',16,1); RETURN; END

DECLARE @Thermal INT = (SELECT TOP 1 print_device_id FROM print_devices
                         WHERE device_code = 'THERMAL' AND deleted_at IS NULL
                         ORDER BY print_device_id);

IF @Thermal IS NULL
BEGIN
    RAISERROR('print_devices dengan device_code = THERMAL tidak ditemukan -- daftarkan printer 80mm dulu.', 16, 1);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM print_job_routes
                WHERE job_type = 'TNI_KARTU' AND deleted_at IS NULL)
    INSERT INTO print_job_routes (job_type, print_device_id, created_by)
    VALUES ('TNI_KARTU', @Thermal, @SeedUserId);

DECLARE @Rute INT = (SELECT COUNT(*) FROM print_job_routes
                      WHERE job_type = 'TNI_KARTU' AND deleted_at IS NULL);
DECLARE @Nama VARCHAR(255) = (SELECT printer_name FROM print_devices WHERE print_device_id = @Thermal);

PRINT CONCAT('route TNI_KARTU: ', @Rute, ' (harus 1) -> printer "', @Nama, '"');
GO
