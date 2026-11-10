/* =============================================================
   Prompt 88 -- printer jaringan (TCP) + satu job type -> banyak device tujuan.

   Catatan nama: prompt menyebut kolom "connection_type". Tabel ini SUDAH punya kolom
   tipe device sejak Prompt 77 -- print_devices.transport (WINDOWS | ANDROID_BT). Sesuai
   prompt ("pakai kolom itu dan tambahkan nilai TCP, jangan buat kolom kembar"), yang
   dilakukan di sini: CHECK transport diperluas jadi WINDOWS | TCP | ANDROID_BT.

   Isi:
     1. print_devices: transport + 'TCP', kolom host/port (wajib untuk TCP), device_group.
     2. Seed device LABEL_ATAS (Xprinter XP-D4601B, 192.168.8.51:9100).
     3. print_job_routes: unique (job_type) -> unique (job_type, print_device_id).

   SP yang ikut berubah (jalankan SETELAH file ini):
     sql/sp_PrintJob_Manage.sql          (SIS_PrintJob_ResolveDevice baru, Claim, Report)
     sql/alter_print_jobs_dryrun.sql     (SIS_PrintJobDryRun_Claim/_Seed)
     sql/sp_PrintDevice_Manage.sql       (device + routing + test print, file baru)
     sql/sp_Bundle_Manage.sql            (SIS_Bundle_Manage, SIS_Bundle_ReprintLabel)
     sql/sp_BundleSplit_Manage.sql       (SIS_BundleSplit_Manage, SIS_BundleSplit_PrintLabel)
     sql/cutting/sp_78_Cutting.sql       (SIS_CuttingBundle_Print)

   Idempotent -- tidak ada recreate table (hanya ADD COLUMN / ganti constraint & index).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------- 1a. transport: tambah nilai TCP ----------
IF EXISTS (SELECT 1 FROM sys.check_constraints
            WHERE name = 'CK_print_devices_transport'
              AND definition NOT LIKE '%TCP%')
    ALTER TABLE print_devices DROP CONSTRAINT CK_print_devices_transport;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_print_devices_transport')
    ALTER TABLE print_devices ADD CONSTRAINT CK_print_devices_transport
        CHECK (transport IN ('WINDOWS','TCP','ANDROID_BT'));
GO

-- ---------- 1b. host + port ----------
IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'host')
    ALTER TABLE print_devices ADD host VARCHAR(100) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'port')
    ALTER TABLE print_devices ADD port INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_print_devices_tcp_host')
    ALTER TABLE print_devices ADD CONSTRAINT CK_print_devices_tcp_host
        CHECK (transport <> 'TCP' OR (host IS NOT NULL AND port IS NOT NULL AND port BETWEEN 1 AND 65535));
GO

-- ---------- 1c. device_group ----------
-- LABEL_BUNDLE (label 10x5 cm TSPL), LABEL_BENANG (label 30x20 mm TSPL, HP),
-- STRUK_80 (thermal 80 mm TOKEN). Tanpa CHECK supaya grup baru cukup diketik di admin.
IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'device_group')
    ALTER TABLE print_devices ADD device_group VARCHAR(30) NULL;
GO

-- Isi baris lama: HP Bluetooth -> LABEL_BENANG, mode TOKEN -> STRUK_80, sisanya
-- (TSC & printer RAW_TSPL PC lain) -> LABEL_BUNDLE.
UPDATE print_devices
SET device_group = CASE
        WHEN transport = 'ANDROID_BT' THEN 'LABEL_BENANG'
        WHEN render_mode = 'TOKEN'    THEN 'STRUK_80'
        ELSE 'LABEL_BUNDLE'
    END
WHERE device_group IS NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns
            WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'device_group' AND is_nullable = 1)
    ALTER TABLE print_devices ALTER COLUMN device_group VARCHAR(30) NOT NULL;
GO

-- Default supaya script seed lama (alter_48 di DB baru) tetap bisa INSERT tanpa kolom ini.
-- SP device baru selalu mengisi grup secara eksplisit.
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_print_devices_device_group')
    ALTER TABLE print_devices ADD CONSTRAINT DF_print_devices_device_group
        DEFAULT 'LABEL_BUNDLE' FOR device_group;
GO

-- ---------- 2. seed device LABEL_ATAS ----------
DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

IF NOT EXISTS (SELECT 1 FROM print_devices WHERE device_code = 'LABEL_ATAS' AND deleted_at IS NULL)
    INSERT INTO print_devices
        (device_code, device_name, printer_name, render_mode, chars_per_line, chars_per_line_small,
         is_active, transport, host, port, device_group, created_at, created_by)
    VALUES
        ('LABEL_ATAS', N'Label Lantai Atas (XP-D4601B)', 'TCP 192.168.8.51:9100', 'RAW_TSPL', 48, 64,
         1, 'TCP', '192.168.8.51', 9100, 'LABEL_BUNDLE', SYSDATETIME(), @AdminUserId);
GO

-- ---------- 3. routing: banyak device per job type ----------
IF EXISTS (SELECT 1 FROM sys.indexes
            WHERE name = 'UX_print_job_routes_type' AND object_id = OBJECT_ID('dbo.print_job_routes'))
    DROP INDEX UX_print_job_routes_type ON print_job_routes;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'UX_print_job_routes_type_device' AND object_id = OBJECT_ID('dbo.print_job_routes'))
    CREATE UNIQUE INDEX UX_print_job_routes_type_device
        ON print_job_routes(job_type, print_device_id) WHERE deleted_at IS NULL;
GO
