/* =============================================================
   PDH TNI AD -- nama petugas DIKENALI DARI PERANGKAT (2026-10-06).

   Permintaan owner: tabel / pemilih petugas DIHILANGKAN. Setiap perangkat
   punya SATU nama petugas (kolom tni.perangkat.nama_petugas). Jejak kerja
   menyimpan PERANGKAT yang mengerjakan, dan nama yang tampil diambil dari
   perangkat itu.

     tni.perangkat.nama_petugas            -- baru, wajib
     personel.printed/set/boxed_petugas_id -> printed/set/boxed_perangkat_id
     box.packed/shipped_petugas_id         -> packed/shipped_perangkat_id
     stok_mutasi / pembatalan / komplain .petugas_id -> .perangkat_id
     tni.petugas                           -> DIARSIPKAN ke tni.petugas_arsip_75
                                              lalu DI-DROP (beserta SP-nya)

   Data jejak lama dipindah: petugas X -> perangkat tempat X di-assign.
   Nama per perangkat diisi dari petugas AKTIF ber-id terkecil di perangkat itu.

   KONSEKUENSI (disetujui owner): mengganti nama petugas sebuah perangkat ikut
   mengganti nama di riwayat lama -- nama selalu dibaca dari perangkat.

   created_by / updated_by TETAP user id (user sistem tni_system).

   Idempotent: setiap langkah dicek dulu, aman dijalankan ulang.
   ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ------------------------------------------------------------
-- 1. tni.perangkat.nama_petugas
-- ------------------------------------------------------------
IF COL_LENGTH('tni.perangkat','nama_petugas') IS NULL
    ALTER TABLE tni.perangkat ADD nama_petugas varchar(150) null;
GO

IF OBJECT_ID('tni.petugas','U') IS NOT NULL
    EXEC sp_executesql N'
        UPDATE pr
        SET nama_petugas = x.nama
        FROM tni.perangkat pr
        CROSS APPLY (SELECT TOP 1 pt.nama
                       FROM tni.petugas pt
                      WHERE pt.perangkat_id = pr.perangkat_id
                        AND pt.deleted_at IS NULL AND pt.is_active = 1
                      ORDER BY pt.petugas_id) x
        WHERE pr.nama_petugas IS NULL;';
GO

-- perangkat tanpa petugas sama sekali -> pakai nama perangkat supaya NOT NULL aman
UPDATE tni.perangkat SET nama_petugas = perangkat_name WHERE nama_petugas IS NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('tni.perangkat')
           AND name = 'nama_petugas' AND is_nullable = 1)
    ALTER TABLE tni.perangkat ALTER COLUMN nama_petugas varchar(150) not null;
GO

-- ------------------------------------------------------------
-- 2. kolom jejak: *_petugas_id -> *_perangkat_id
--    Pola tiap kolom: tambah kolom baru (FK perangkat) -> salin data lewat
--    tni.petugas.perangkat_id -> lepas FK lama -> drop kolom lama.
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#kolom') IS NOT NULL DROP TABLE #kolom;
CREATE TABLE #kolom (tbl sysname, lama sysname, baru sysname, fk sysname);
INSERT INTO #kolom VALUES
 ('personel',    'printed_petugas_id', 'printed_perangkat_id', 'FK_tni_personel_printed_perangkat'),
 ('personel',    'set_petugas_id',     'set_perangkat_id',     'FK_tni_personel_set_perangkat'),
 ('personel',    'boxed_petugas_id',   'boxed_perangkat_id',   'FK_tni_personel_boxed_perangkat'),
 ('box',         'packed_petugas_id',  'packed_perangkat_id',  'FK_tni_box_packed_perangkat'),
 ('box',         'shipped_petugas_id', 'shipped_perangkat_id', 'FK_tni_box_shipped_perangkat'),
 ('stok_mutasi', 'petugas_id',         'perangkat_id',         'FK_tni_stok_mutasi_perangkat'),
 ('pembatalan',  'petugas_id',         'perangkat_id',         'FK_tni_pembatalan_perangkat'),
 ('komplain',    'petugas_id',         'perangkat_id',         'FK_tni_komplain_perangkat');

DECLARE @tbl sysname, @lama sysname, @baru sysname, @fk sysname, @sql nvarchar(max), @fkLama sysname;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, lama, baru, fk FROM #kolom;
OPEN c;
FETCH NEXT FROM c INTO @tbl, @lama, @baru, @fk;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- a. kolom baru
    IF COL_LENGTH('tni.' + @tbl, @baru) IS NULL
    BEGIN
        SET @sql = N'ALTER TABLE tni.' + QUOTENAME(@tbl) + N' ADD ' + QUOTENAME(@baru) + N' int null '
                 + N'CONSTRAINT ' + QUOTENAME(@fk) + N' FOREIGN KEY REFERENCES tni.perangkat(perangkat_id);';
        EXEC sp_executesql @sql;
    END

    IF COL_LENGTH('tni.' + @tbl, @lama) IS NOT NULL
    BEGIN
        -- b. salin data: petugas -> perangkat tempat petugas itu di-assign
        IF OBJECT_ID('tni.petugas','U') IS NOT NULL
        BEGIN
            SET @sql = N'UPDATE t SET ' + QUOTENAME(@baru) + N' = pt.perangkat_id '
                     + N'FROM tni.' + QUOTENAME(@tbl) + N' t '
                     + N'JOIN tni.petugas pt ON pt.petugas_id = t.' + QUOTENAME(@lama) + N' '
                     + N'WHERE t.' + QUOTENAME(@baru) + N' IS NULL;';
            EXEC sp_executesql @sql;
        END

        -- c. lepas FK lama (nama FK komplain buatan sistem -> dicari dinamis)
        SET @fkLama = NULL;
        SELECT @fkLama = fk.name
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = fk.object_id
        JOIN sys.columns col ON col.object_id = fc.parent_object_id AND col.column_id = fc.parent_column_id
        WHERE fk.parent_object_id = OBJECT_ID('tni.' + @tbl) AND col.name = @lama;

        IF @fkLama IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE tni.' + QUOTENAME(@tbl) + N' DROP CONSTRAINT ' + QUOTENAME(@fkLama) + N';';
            EXEC sp_executesql @sql;
        END

        -- d. drop kolom lama
        SET @sql = N'ALTER TABLE tni.' + QUOTENAME(@tbl) + N' DROP COLUMN ' + QUOTENAME(@lama) + N';';
        EXEC sp_executesql @sql;
    END

    FETCH NEXT FROM c INTO @tbl, @lama, @baru, @fk;
END
CLOSE c;
DEALLOCATE c;
GO

-- ------------------------------------------------------------
-- 3. arsipkan lalu drop tni.petugas + SP-nya
-- ------------------------------------------------------------
IF OBJECT_ID('tni.petugas','U') IS NOT NULL AND OBJECT_ID('tni.petugas_arsip_75','U') IS NULL
    SELECT * INTO tni.petugas_arsip_75 FROM tni.petugas;
GO

IF OBJECT_ID('tni.SIS_Petugas_List','P')   IS NOT NULL DROP PROCEDURE tni.SIS_Petugas_List;
IF OBJECT_ID('tni.SIS_Petugas_Manage','P') IS NOT NULL DROP PROCEDURE tni.SIS_Petugas_Manage;
GO

IF OBJECT_ID('tni.petugas','U') IS NOT NULL DROP TABLE tni.petugas;
GO

PRINT 'Petugas kini dikenali dari perangkat (tni.perangkat.nama_petugas).';
GO
