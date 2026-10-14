/* =============================================================
   Module Stok Benang (Prompt 73) -- routing job cetak label 30x20 mm.

   Dua job type baru diarahkan ke device `LABEL` yang sudah ada
   (TSC TTP-244 Pro, render_mode RAW_TSPL). print_devices TIDAK diubah.

   Owner bisa:
   - mengganti roll printer itu ke 30x20 mm (tidak perlu SQL), atau
   - memindah route ke device Android (Prompt 77) cukup dengan UPDATE
     print_job_routes di bawah -- tanpa perubahan kode.

   Idempotent: aman dijalankan berulang.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @LabelDeviceId INT =
    (SELECT print_device_id FROM print_devices
      WHERE device_code = 'LABEL' AND deleted_at IS NULL);

IF @LabelDeviceId IS NULL
BEGIN
    RAISERROR('Device cetak dengan device_code = ''LABEL'' tidak ditemukan -- jalankan sql/alter_48_print_devices.sql dulu.', 16, 1);
    RETURN;
END

INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
SELECT jt.job_type, @LabelDeviceId, GETDATE(), 1
FROM (VALUES ('THREAD_SKU_LABEL'), ('THREAD_SPLIT_LABEL')) AS jt(job_type)
WHERE NOT EXISTS (
    SELECT 1 FROM print_job_routes r
    WHERE r.job_type = jt.job_type AND r.deleted_at IS NULL
);
GO

SELECT r.job_type AS JobType, d.device_code AS DeviceCode, d.printer_name AS PrinterName,
       d.render_mode AS RenderMode, d.is_active AS DeviceAktif
FROM print_job_routes r
INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
WHERE r.job_type IN ('THREAD_SKU_LABEL','THREAD_SPLIT_LABEL')
  AND r.deleted_at IS NULL;
GO
