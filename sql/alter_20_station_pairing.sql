-- Prompt 20: pairing station sekali pakai + link autologin (rotasi station_token).
-- Idempotent, aman dijalankan berulang.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stations') AND name = 'pairing_code')
BEGIN
    ALTER TABLE stations ADD pairing_code varchar(10) null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stations') AND name = 'pairing_code_expires_at')
BEGIN
    ALTER TABLE stations ADD pairing_code_expires_at datetime2 null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stations') AND name = 'paired_at')
BEGIN
    ALTER TABLE stations ADD paired_at datetime2 null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_stations_pairing_code' AND object_id = OBJECT_ID('stations'))
    CREATE UNIQUE INDEX UX_stations_pairing_code ON stations(pairing_code) WHERE pairing_code IS NOT NULL AND deleted_at IS NULL;
GO
