-- Prompt 48: routing printer lewat tabel, menggantikan PrinterName tunggal di appsettings.
-- Idempotent -- aman dijalankan berkali-kali / terhadap DB yang belum atau sudah punya
-- sebagian dari perubahan ini.
--
-- Route field trip (kondisi lapangan saat ini, cuma 2 printer fisik):
--   - Semua job_type yang dirakit TSPL (BUNDLE_LABEL, PACK_LABEL, REJECT_NOTE) -> device LABEL
--     (render_mode RAW_TSPL, TsplBuilder.cs TIDAK berubah).
--   - Sisanya (job_type struk ESC/POS: KUPON_BORONGAN, REKAP_PRODUKSI, REKAP_KARYAWAN) ->
--     device THERMAL (render_mode TOKEN). Hanya KUPON_BORONGAN yang sudah punya SP render
--     (SIS_Print_KuponBorongan, lihat sql/sp_Print_Render.sql) -- REKAP_PRODUKSI/REKAP_KARYAWAN
--     akan gagal dengan pesan jelas dari SIS_Print_Dispatch ("belum punya SP render") sampai
--     prompt lanjutan menambah SP render-nya; job tetap tercatat (retry lalu ERROR), tidak
--     hilang diam-diam.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'print_devices')
BEGIN
    CREATE TABLE print_devices(
        print_device_id int primary key identity(1,1),
        device_code varchar(30) not null,
        device_name varchar(150) not null,
        printer_name varchar(255) not null,
        render_mode varchar(20) not null
            constraint CK_print_devices_render_mode check (render_mode in ('TOKEN','RAW_TSPL')),
        chars_per_line int not null default 48,
        chars_per_line_small int not null default 64,
        is_active bit not null default 1,
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_print_devices_code')
    CREATE UNIQUE INDEX UX_print_devices_code ON print_devices(device_code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'print_job_routes')
BEGIN
    CREATE TABLE print_job_routes(
        print_job_route_id int primary key identity(1,1),
        job_type varchar(30) not null,
        print_device_id int not null
            constraint FK_pjr_print_devices foreign key references print_devices(print_device_id),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_print_job_routes_type')
    CREATE UNIQUE INDEX UX_print_job_routes_type ON print_job_routes(job_type) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('print_jobs') AND name = 'print_device_id')
    ALTER TABLE print_jobs ADD print_device_id int null;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_print_jobs_print_devices')
    ALTER TABLE print_jobs ADD CONSTRAINT FK_print_jobs_print_devices
        FOREIGN KEY (print_device_id) REFERENCES print_devices(print_device_id);
GO

-- Seed 2 device (idempotent per device_code). printer_name LABEL diambil dari nilai
-- PrinterName yang selama ini dipakai TerakarsaApp.PrintService untuk TSC (lihat
-- appsettings.json PrintService) -- fallback 'TSC TTP-244 Pro' kalau tidak ada baris.
DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

IF NOT EXISTS (SELECT 1 FROM print_devices WHERE device_code = 'LABEL' AND deleted_at IS NULL)
    INSERT INTO print_devices (device_code, device_name, printer_name, render_mode, chars_per_line, chars_per_line_small, is_active, created_at, created_by)
    VALUES ('LABEL', N'Label Bundle (TSC TTP-244 Pro)', 'TSC TTP-244 Pro', 'RAW_TSPL', 48, 64, 1, SYSDATETIME(), @AdminUserId);

IF NOT EXISTS (SELECT 1 FROM print_devices WHERE device_code = 'THERMAL' AND deleted_at IS NULL)
    INSERT INTO print_devices (device_code, device_name, printer_name, render_mode, chars_per_line, chars_per_line_small, is_active, created_at, created_by)
    VALUES ('THERMAL', N'Struk Thermal (Iware XS-80BT)', 'Iware XS-80BT', 'TOKEN', 48, 64, 1, SYSDATETIME(), @AdminUserId);
GO

-- Seed route (idempotent per job_type). Semua jalur TSPL -> LABEL, sisanya (struk ESC/POS) -> THERMAL.
DECLARE @AdminUserId2 INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @LabelDeviceId INT = (SELECT print_device_id FROM print_devices WHERE device_code = 'LABEL' AND deleted_at IS NULL);
DECLARE @ThermalDeviceId INT = (SELECT print_device_id FROM print_devices WHERE device_code = 'THERMAL' AND deleted_at IS NULL);

;WITH RouteSeed AS (
    SELECT 'BUNDLE_LABEL' AS job_type, @LabelDeviceId AS print_device_id
    UNION ALL SELECT 'PACK_LABEL', @LabelDeviceId
    UNION ALL SELECT 'REJECT_NOTE', @LabelDeviceId
    UNION ALL SELECT 'KUPON_BORONGAN', @ThermalDeviceId
    UNION ALL SELECT 'REKAP_PRODUKSI', @ThermalDeviceId
    UNION ALL SELECT 'REKAP_KARYAWAN', @ThermalDeviceId
)
INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
SELECT rs.job_type, rs.print_device_id, SYSDATETIME(), @AdminUserId2
FROM RouteSeed rs
WHERE NOT EXISTS (SELECT 1 FROM print_job_routes pjr WHERE pjr.job_type = rs.job_type AND pjr.deleted_at IS NULL);
GO
