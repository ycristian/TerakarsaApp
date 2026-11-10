-- Alter 87: flag stations.allow_all_divisions.
-- Stasiun dengan flag ini boleh pindah divisi per sesi dari layar "Pilih Operator" di /station.
-- Divisi pilihan dikirim perangkat lewat header X-Station-Division, divalidasi
-- SIS_Station_GetByToken (sp_Station_Select.sql). Tanpa flag, header itu diabaikan dan
-- divisi tetap stations.division_id.
--
-- Urutan jalan: script ini dulu, lalu sp_Station_Select.sql dan sp_Station_Manage.sql,
-- BARU deploy API/Client (DTO baru menuntut kolom AllowAllDivisions dari SP).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'allow_all_divisions'
)
BEGIN
    ALTER TABLE stations ADD allow_all_divisions bit not null default 0;
END
GO
