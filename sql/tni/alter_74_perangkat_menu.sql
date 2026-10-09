/* =============================================================
   PDH TNI AD -- akses MENU per perangkat (2026-10-06).

   Permintaan owner: setiap perangkat hanya punya akses ke menu tertentu.
   Satu baris per (perangkat, menu) yang DIIZINKAN. Kode menu tetap:

     PERINTAH_KERJA  SCAN  BOX  STOK  PERSONEL  DASHBOARD  IMPORT  POLA

   Perangkat yang SUDAH ADA diberi SEMUA menu supaya tidak ada yang tiba-tiba
   terkunci; perangkat baru juga default semua menu (SIS_Perangkat_Manage).

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tni.perangkat_menu','U') IS NULL
CREATE TABLE tni.perangkat_menu(
 perangkat_menu_id int primary key identity(1,1),
 perangkat_id int not null
   constraint FK_tni_perangkat_menu_perangkat foreign key references tni.perangkat(perangkat_id),
 menu_code varchar(30) not null
   constraint CK_tni_perangkat_menu_code check (menu_code in
     ('PERINTAH_KERJA','SCAN','BOX','STOK','PERSONEL','DASHBOARD','IMPORT','POLA')),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_menu' AND object_id = OBJECT_ID('tni.perangkat_menu'))
    CREATE UNIQUE INDEX UX_tni_perangkat_menu ON tni.perangkat_menu(perangkat_id, menu_code) WHERE deleted_at IS NULL;
GO

-- Perangkat lama yang belum punya baris menu sama sekali -> semua menu.
INSERT INTO tni.perangkat_menu (perangkat_id, menu_code, created_by)
SELECT p.perangkat_id, m.code, p.created_by
FROM tni.perangkat p
CROSS JOIN (VALUES ('PERINTAH_KERJA'),('SCAN'),('BOX'),('STOK'),
                   ('PERSONEL'),('DASHBOARD'),('IMPORT'),('POLA')) m(code)
WHERE p.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM tni.perangkat_menu pm WHERE pm.perangkat_id = p.perangkat_id);
GO

PRINT 'tni.perangkat_menu siap.';
GO
