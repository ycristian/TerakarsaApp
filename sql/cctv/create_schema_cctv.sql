/* =============================================================
   TMOS - Module CCTV (Prompt 91-94) - Skema `cctv`
   FILE CANONICAL untuk seluruh tabel schema cctv.
   Tabel schema dbo TIDAK disentuh dari file ini
   (sql/create_tables_tmos_final.sql tetap canonical untuk dbo).

   Aturan:
   1. snake_case. NVARCHAR untuk teks (nama kamera/area bebas ketik).
   2. Kode unik via filtered unique index WHERE deleted_at IS NULL.
   3. created_by/updated_by/deleted_by: int tanpa FK -- sama dengan tabel
      dbo, tni, inv (selalu Users.Id).
   4. TIDAK ADA kolom user/password/kode verifikasi kamera. Terakarsa hanya
      bicara ke MediaMTX (path), tidak pernah langsung ke kamera.
   5. Hanya MEMBACA dbo.resources & dbo.divisions (FK tautan).

   Idempotent: tiap objek dibungkus IF ... IS NULL / NOT EXISTS.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'cctv')
    EXEC('CREATE SCHEMA cctv');
GO

-- ============ 1. KAMERA ============
-- Satu baris = satu path MediaMTX (mis. cam8_83). IP / serial / channel NVR hanya
-- data inventaris -- tidak pernah dipakai untuk menghubungi kamera.
IF OBJECT_ID('cctv.cameras','U') IS NULL
CREATE TABLE cctv.cameras(
 camera_id int primary key identity(1,1),
 name nvarchar(100) not null,               -- nama tampil
 area nvarchar(50) null,                    -- teks bebas: Cutting, Sewing, Gudang, ...
 mtx_path nvarchar(50) not null,            -- path MediaMTX, mis. cam8_83
 ip_address nvarchar(45) null,              -- inventaris saja
 serial_no nvarchar(30) null,               -- inventaris saja
 nvr_channel int null,                      -- inventaris saja (NVR cadangan)
 sort_order int not null default 0,
 is_visible bit not null default 1,         -- tampil di grid live
 note nvarchar(200) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 -- hanya huruf/angka/_/- (path ini ikut dipakai di URL proxy API)
 constraint CK_cctv_cameras_mtx_path check (mtx_path <> '' AND mtx_path NOT LIKE '%[^A-Za-z0-9_-]%')
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_cctv_cameras_mtx_path' AND object_id = OBJECT_ID('cctv.cameras'))
    CREATE UNIQUE INDEX UX_cctv_cameras_mtx_path ON cctv.cameras(mtx_path) WHERE deleted_at IS NULL;
GO

-- ============ 2. TAUTAN KAMERA -> PRODUKSI ============
-- Kamera <-> resource (line/station) ATAU kamera <-> divisi; tepat satu terisi.
-- Dipakai tombol "Lihat CCTV" (Prompt 94): cari dari resource dulu, lalu divisi.
IF OBJECT_ID('cctv.camera_links','U') IS NULL
CREATE TABLE cctv.camera_links(
 camera_link_id int primary key identity(1,1),
 camera_id int not null
   constraint FK_cctv_camera_links_cameras foreign key references cctv.cameras(camera_id),
 resource_id int null
   constraint FK_cctv_camera_links_resources foreign key references dbo.resources(resource_id),
 division_id int null
   constraint FK_cctv_camera_links_divisions foreign key references dbo.divisions(division_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_cctv_camera_links_one_target check (
   (resource_id IS NOT NULL AND division_id IS NULL) OR
   (resource_id IS NULL AND division_id IS NOT NULL))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_cctv_camera_links_resource' AND object_id = OBJECT_ID('cctv.camera_links'))
    CREATE UNIQUE INDEX UX_cctv_camera_links_resource ON cctv.camera_links(camera_id, resource_id)
        WHERE deleted_at IS NULL AND resource_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_cctv_camera_links_division' AND object_id = OBJECT_ID('cctv.camera_links'))
    CREATE UNIQUE INDEX UX_cctv_camera_links_division ON cctv.camera_links(camera_id, division_id)
        WHERE deleted_at IS NULL AND division_id IS NOT NULL;
GO

-- Pencarian kamera untuk sebuah transaksi (Prompt 94): dari resource / divisi.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cctv_camera_links_resource_lookup' AND object_id = OBJECT_ID('cctv.camera_links'))
    CREATE INDEX IX_cctv_camera_links_resource_lookup ON cctv.camera_links(resource_id) INCLUDE (camera_id)
        WHERE deleted_at IS NULL AND resource_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cctv_camera_links_division_lookup' AND object_id = OBJECT_ID('cctv.camera_links'))
    CREATE INDEX IX_cctv_camera_links_division_lookup ON cctv.camera_links(division_id) INCLUDE (camera_id)
        WHERE deleted_at IS NULL AND division_id IS NOT NULL;
GO
