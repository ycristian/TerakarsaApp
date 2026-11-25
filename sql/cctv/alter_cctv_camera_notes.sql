/* =============================================================
   TMOS - Module CCTV - Catatan kejadian di rekaman (tag waktu)
   Satu baris = satu kejadian pada satu kamera di satu detik tertentu
   (mis. 25 Nov 2026 11:17:05, tag "Barang masuk", catatan bebas).
   Dipakai halaman Playback: penanda di garis waktu + daftar kejadian per tanggal
   yang diurutkan waktu (satu kamera / semua kamera).

   event_at = waktu WIB (UTC+7) tanpa offset, sama dengan jam di rekaman.
   Catatan TETAP ada walaupun rekamannya sudah terhapus otomatis (30 hari).

   Urutan jalan manual:
     1. script ini
     2. sql/cctv/sp_cctv_camera_note.sql

   Idempotent. Canonical: sql/cctv/create_schema_cctv.sql (ikut diperbarui).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('cctv.camera_notes','U') IS NULL
CREATE TABLE cctv.camera_notes(
 note_id int primary key identity(1,1),
 camera_id int not null
   constraint FK_cctv_camera_notes_cameras foreign key references cctv.cameras(camera_id),
 event_at datetime2(0) not null,            -- WIB, ketelitian detik
 tag nvarchar(30) null,                     -- teks bebas pendek, mis. "Barang masuk"
 note nvarchar(500) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Daftar kejadian per tanggal (semua kamera) dan per kamera.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cctv_camera_notes_event_at' AND object_id = OBJECT_ID('cctv.camera_notes'))
    CREATE INDEX IX_cctv_camera_notes_event_at ON cctv.camera_notes(event_at) INCLUDE (camera_id)
        WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cctv_camera_notes_camera' AND object_id = OBJECT_ID('cctv.camera_notes'))
    CREATE INDEX IX_cctv_camera_notes_camera ON cctv.camera_notes(camera_id, event_at)
        WHERE deleted_at IS NULL;
GO
