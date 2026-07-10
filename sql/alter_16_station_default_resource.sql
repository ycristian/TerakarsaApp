-- Migrasi Prompt 16: resource bawaan per stasiun (1 device = 1 resource), dengan opsi
-- kunci (allow_resource_change = 0) supaya operator tidak perlu pilih tiap sesi.
-- Idempotent, aman dijalankan berulang.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stations') AND name = 'default_resource_id')
BEGIN
    ALTER TABLE stations ADD default_resource_id int null
        CONSTRAINT FK_stations_default_resource FOREIGN KEY REFERENCES resources(resource_id);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stations') AND name = 'allow_resource_change')
BEGIN
    ALTER TABLE stations ADD allow_resource_change bit not null default 1;
END
GO
