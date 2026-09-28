-- Ad hoc (2026-09-01): routing print_job_routes utk job_type baru REKAP_PENGAMBILAN
-- (SIS_Report_BundlePengambilanPrint + SIS_Print_RekapPengambilan, sql/sp_Report_Bundle.sql &
-- sql/sp_Print_Render.sql) -- device sama dengan REKAP_PRODUKSI/REKAP_WIP (THERMAL).
-- Idempotent -- aman dijalankan berkali-kali.
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM print_job_routes WHERE job_type = 'REKAP_PENGAMBILAN' AND deleted_at IS NULL)
BEGIN
    INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
    SELECT 'REKAP_PENGAMBILAN', pd.print_device_id, SYSDATETIME(), 1
    FROM print_devices pd
    WHERE pd.device_code = 'THERMAL' AND pd.deleted_at IS NULL;
END
