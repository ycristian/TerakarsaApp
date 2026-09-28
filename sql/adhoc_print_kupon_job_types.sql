-- Ad hoc (2026-09-01): daftar job_type "kupon" (thermal, render_mode TOKEN) dipindah dari array
-- hardcode C# (Worker.cs KuponJobTypes) ke tabel ini -- supaya nambah job_type struk BARU
-- (SP render TOKEN generik + print_job_routes) TIDAK butuh update/republish/restart
-- TerakarsaApp.PrintService lagi, cukup INSERT baris baru di sini. PrintService fetch list ini
-- SETIAP siklus poll (GET api/print/kupon-job-types, lihat PrintController.cs) -- bukan cache
-- sekali saat startup, supaya baris baru langsung kepakai tanpa restart service.
--
-- TIDAK berlaku utk job_type label (BUNDLE_LABEL/PACK_LABEL/REJECT_NOTE, render_mode RAW_TSPL)
-- -- TsplBuilder.cs punya layout spesifik per jenis label di C#, jadi TETAP hardcode di
-- Worker.cs (LabelJobTypes), TIDAK dipindah ke sini.
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('print_kupon_job_types') AND type = 'U')
BEGIN
    CREATE TABLE print_kupon_job_types (
        print_kupon_job_type_id INT IDENTITY(1,1) PRIMARY KEY,
        job_type    VARCHAR(30) NOT NULL,
        created_at  DATETIME2 NOT NULL,
        created_by  INT NOT NULL,
        updated_at  DATETIME2 NULL,
        updated_by  INT NULL,
        deleted_at  DATETIME2 NULL,
        deleted_by  INT NULL
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('print_kupon_job_types') AND name = 'UX_print_kupon_job_types_job_type'
)
BEGIN
    CREATE UNIQUE INDEX UX_print_kupon_job_types_job_type ON print_kupon_job_types (job_type)
    WHERE deleted_at IS NULL;
END
GO

-- Seed idempotent -- 5 job_type yang sebelumnya hardcode di Worker.cs KuponJobTypes.
IF NOT EXISTS (SELECT 1 FROM print_kupon_job_types WHERE job_type = 'KUPON_BORONGAN' AND deleted_at IS NULL)
    INSERT INTO print_kupon_job_types (job_type, created_at, created_by) VALUES ('KUPON_BORONGAN', SYSDATETIME(), 1);
GO
IF NOT EXISTS (SELECT 1 FROM print_kupon_job_types WHERE job_type = 'REKAP_PRODUKSI' AND deleted_at IS NULL)
    INSERT INTO print_kupon_job_types (job_type, created_at, created_by) VALUES ('REKAP_PRODUKSI', SYSDATETIME(), 1);
GO
IF NOT EXISTS (SELECT 1 FROM print_kupon_job_types WHERE job_type = 'REKAP_KARYAWAN' AND deleted_at IS NULL)
    INSERT INTO print_kupon_job_types (job_type, created_at, created_by) VALUES ('REKAP_KARYAWAN', SYSDATETIME(), 1);
GO
IF NOT EXISTS (SELECT 1 FROM print_kupon_job_types WHERE job_type = 'REKAP_WIP' AND deleted_at IS NULL)
    INSERT INTO print_kupon_job_types (job_type, created_at, created_by) VALUES ('REKAP_WIP', SYSDATETIME(), 1);
GO
IF NOT EXISTS (SELECT 1 FROM print_kupon_job_types WHERE job_type = 'REKAP_PENGAMBILAN' AND deleted_at IS NULL)
    INSERT INTO print_kupon_job_types (job_type, created_at, created_by) VALUES ('REKAP_PENGAMBILAN', SYSDATETIME(), 1);
GO
