-- Alter 88 (Prompt 85): kode login stasiun terkunci + identitas perangkat pemegang token.
--
-- - pairing_code_locked = 1: pairing_code permanen (10 karakter), bisa diklaim berulang,
--   tidak hangus. 0 = perilaku Prompt 20 (5 huruf, 15 menit, sekali pakai).
-- - paired_device_id/paired_device_name: perangkat yang terakhir klaim -- dipakai peringatan
--   "DIPAKAI|" saat perangkat LAIN mencoba klaim (SIS_Station_Manage CLAIM_PAIRING).
-- - last_seen_at: terakhir perangkat pemegang token memanggil API (aksi TOUCH, maks 1x/menit).
--
-- Hanya ADD COLUMN -- station_token tidak disentuh, jadi perangkat yang sedang login tetap
-- login. Aman dijalankan saat stasiun sedang dipakai.
--
-- Urutan jalan: alter_87 (allow_all_divisions) dulu, lalu script ini, lalu
-- sp_Station_Manage.sql dan sp_Station_Select.sql, BARU deploy API, lalu Client.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'pairing_code_locked'
)
BEGIN
    ALTER TABLE stations ADD pairing_code_locked bit not null
        CONSTRAINT DF_stations_pairing_code_locked DEFAULT 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'paired_device_id'
)
BEGIN
    ALTER TABLE stations ADD paired_device_id varchar(64) null;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'paired_device_name'
)
BEGIN
    ALTER TABLE stations ADD paired_device_name nvarchar(100) null;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'last_seen_at'
)
BEGIN
    ALTER TABLE stations ADD last_seen_at datetime2 null;
END
GO
