-- Ad hoc (2026-08-28): routing print_job_routes utk job_type baru REKAP_WIP (SIS_Report_WipPrint
-- + SIS_Print_RekapWip, sql/sp_Report_RekapStruk.sql & sql/sp_Print_Render.sql) -- device sama
-- dengan REKAP_PRODUKSI/KUPON_BORONGAN (THERMAL, print_device_id 2, pola dari alter_48_print_devices.sql).
-- Idempotent -- aman dijalankan berkali-kali.
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM print_job_routes WHERE job_type = 'REKAP_WIP' AND deleted_at IS NULL)
BEGIN
    INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
    SELECT 'REKAP_WIP', pd.print_device_id, SYSDATETIME(), 1
    FROM print_devices pd
    WHERE pd.device_code = 'THERMAL' AND pd.deleted_at IS NULL;
END
