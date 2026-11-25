/* =============================================================
   TMOS - Module CCTV (Prompt 97) - Kualitas rekaman per kamera
   Tambah kolom ke cctv.cameras:
     record_quality            : 'SUB' | 'MAIN', NOT NULL, default 'SUB' (+ CHECK)
     record_quality_updated_at : kapan terakhir diganti (nullable)
     record_quality_updated_by : user id yang mengganti (nullable, int tanpa FK
                                 -- sama dengan updated_by di schema cctv)

   Database = sumber kebenaran. API TMOS menyinkronkan source path MediaMTX
   (lewat API MediaMTX, bukan mediamtx.yml) ke nilai record_quality.
   TIDAK ada kolom URL / user / kode RTSP.

   Urutan jalan manual:
     1. script ini
     2. sql/cctv/sp_91_cctv_camera.sql   (SIS_Camera_Manage/List/Get membawa kolom baru)

   Idempotent: tiap kolom/constraint dicek dulu.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('cctv.cameras', 'record_quality') IS NULL
    ALTER TABLE cctv.cameras ADD record_quality varchar(4) NOT NULL
        CONSTRAINT DF_cctv_cameras_record_quality DEFAULT 'SUB'
        CONSTRAINT CK_cctv_cameras_record_quality CHECK (record_quality IN ('SUB', 'MAIN'));
GO

-- Jaga-jaga kalau kolom sudah ada tetapi CHECK belum terpasang.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'CK_cctv_cameras_record_quality' AND parent_object_id = OBJECT_ID('cctv.cameras'))
    ALTER TABLE cctv.cameras ADD CONSTRAINT CK_cctv_cameras_record_quality
        CHECK (record_quality IN ('SUB', 'MAIN'));
GO

IF COL_LENGTH('cctv.cameras', 'record_quality_updated_at') IS NULL
    ALTER TABLE cctv.cameras ADD record_quality_updated_at datetime2 NULL;
GO

IF COL_LENGTH('cctv.cameras', 'record_quality_updated_by') IS NULL
    ALTER TABLE cctv.cameras ADD record_quality_updated_by int NULL;
GO
