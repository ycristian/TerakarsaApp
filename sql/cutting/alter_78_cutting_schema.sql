/* =============================================================
   Prompt 78 -- Module Cutting (stok bundle dari hamparan).

   Schema dbo (BUKAN schema baru): dua tabel baru + kolom tambahan di
   bundles & articles. Idempotent, HANYA ADD COLUMN / CREATE TABLE --
   tidak ada tabel yang di-drop/recreate, jadi tidak perlu penampungan
   data sementara (lihat aturan CLAUDE.md).

   Istilah lapangan (claude prompt/module-cutting-keputusan-desain.md):
     hamparan = satu kali hampar kain   -> spreads
     set      = satu tumpukan pola      -> spreads.set_count
     lembar   = tinggi tumpukan per set -> spreads.sheets_per_set
     rincian  = set dibagi per size     -> spread_sizes
     bundle   = potongan dari SATU set  -> bundles (source = 'CUTTING')

   PENTING -- kode bundle cutting TIDAK ditaruh di bundles.serial:
   serial dipakai index unik GLOBAL UX_bundles_serial dan jadi isi QR
   ({PublicBaseUrl}/b/<serial>) yang sudah dikenali scanner station,
   sementara kode hamparan (H06-M-03) sengaja TIDAK unik lintas artikel
   (keputusan desain §4). Karena itu kode cutting disimpan di kolom baru
   cutting_code (unik per ARTIKEL saja) dan serial tetap digenerate
   seperti bundle manual supaya QR + halaman /b/<serial> tidak berubah.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============ 1. spreads (hamparan) ============
IF OBJECT_ID('dbo.spreads', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.spreads(
     spread_id int primary key identity(1,1),
     article_id int not null
       constraint FK_spreads_articles foreign key references articles(article_id),
     spread_code varchar(20) not null,      -- H01, H02, ... urut per artikel, boleh diganti manual
     spread_date date not null,
     set_count int not null,                -- jumlah tumpukan pola
     sheets_per_set int not null,           -- lembar per set
     [status] varchar(10) not null constraint DF_spreads_status default 'DRAFT',   -- DRAFT | PRINTED
     printed_at datetime2 null,
     note varchar(500) null,
     created_at datetime2 not null constraint DF_spreads_created_at default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );
END
GO

-- Unik per artikel, baris hidup saja (pola filtered index CLAUDE.md).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_spreads_article_code' AND object_id = OBJECT_ID('dbo.spreads'))
    CREATE UNIQUE INDEX UX_spreads_article_code ON dbo.spreads(article_id, spread_code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spreads_article_date' AND object_id = OBJECT_ID('dbo.spreads'))
    CREATE INDEX IX_spreads_article_date ON dbo.spreads(article_id, spread_date DESC) WHERE deleted_at IS NULL;
GO

-- ============ 2. spread_sizes (rincian set per size) ============
-- Size diikat lewat article_size_id -- SAMA dengan kolom size yang sudah dipakai
-- bundles (bundles.article_size_id), bukan string size_code; nama size-nya diambil
-- lewat join article_sizes -> size_pack_details.size_name.
-- TIDAK ada soft delete di sini: baris mati bersama header-nya, jadi semua query
-- numbering memfilter lewat spreads.deleted_at IS NULL.
IF OBJECT_ID('dbo.spread_sizes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.spread_sizes(
     spread_size_id int primary key identity(1,1),
     spread_id int not null
       constraint FK_spread_sizes_spreads foreign key references spreads(spread_id),
     article_size_id int not null
       constraint FK_spread_sizes_article_sizes foreign key references article_sizes(article_size_id),
     set_count int not null,
     number_from int not null,   -- lanjut dari MAX(number_to) artikel+size yang sama
     number_to int not null,     -- number_from + set_count * sheets_per_set - 1
     created_at datetime2 not null constraint DF_spread_sizes_created_at default sysdatetime()
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spread_sizes_spread' AND object_id = OBJECT_ID('dbo.spread_sizes'))
    CREATE INDEX IX_spread_sizes_spread ON dbo.spread_sizes(spread_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_spread_sizes_article_size' AND object_id = OBJECT_ID('dbo.spread_sizes'))
    CREATE INDEX IX_spread_sizes_article_size ON dbo.spread_sizes(article_size_id, number_to DESC);
GO

-- ============ 3. kolom baru di bundles ============
IF COL_LENGTH('dbo.bundles', 'spread_id') IS NULL
    ALTER TABLE dbo.bundles ADD spread_id int null
        constraint FK_bundles_spreads foreign key references spreads(spread_id);
GO

IF COL_LENGTH('dbo.bundles', 'spread_size_id') IS NULL
    ALTER TABLE dbo.bundles ADD spread_size_id int null
        constraint FK_bundles_spread_sizes foreign key references spread_sizes(spread_size_id);
GO

IF COL_LENGTH('dbo.bundles', 'cutting_code') IS NULL
    ALTER TABLE dbo.bundles ADD cutting_code varchar(30) null;
GO

IF COL_LENGTH('dbo.bundles', 'set_no') IS NULL
    ALTER TABLE dbo.bundles ADD set_no int null;
GO

IF COL_LENGTH('dbo.bundles', 'bundle_seq') IS NULL
    ALTER TABLE dbo.bundles ADD bundle_seq int null;   -- urut per spread per size (01..NN)
GO

IF COL_LENGTH('dbo.bundles', 'number_from') IS NULL
    ALTER TABLE dbo.bundles ADD number_from int null;
GO

IF COL_LENGTH('dbo.bundles', 'number_to') IS NULL
    ALTER TABLE dbo.bundles ADD number_to int null;
GO

-- Bundle lama = MANUAL (default), tidak disentuh sama sekali.
IF COL_LENGTH('dbo.bundles', 'source') IS NULL
    ALTER TABLE dbo.bundles ADD source varchar(10) not null
        constraint DF_bundles_source default 'MANUAL';
GO

-- Hanya terisi untuk source = 'CUTTING': STOCK (masih di cutting) | TAKEN (diambil Bundling).
IF COL_LENGTH('dbo.bundles', 'stock_status') IS NULL
    ALTER TABLE dbo.bundles ADD stock_status varchar(10) null;
GO

IF COL_LENGTH('dbo.bundles', 'taken_at') IS NULL
    ALTER TABLE dbo.bundles ADD taken_at datetime2 null;
GO

IF COL_LENGTH('dbo.bundles', 'taken_by_resource_id') IS NULL
    ALTER TABLE dbo.bundles ADD taken_by_resource_id int null
        constraint FK_bundles_taken_resources foreign key references resources(resource_id);
GO

IF COL_LENGTH('dbo.bundles', 'needs_reprint') IS NULL
    ALTER TABLE dbo.bundles ADD needs_reprint bit not null
        constraint DF_bundles_needs_reprint default 0;
GO

-- Kode cutting unik per ARTIKEL saja (lintas artikel sengaja boleh sama -- lihat
-- catatan di kepala file). cutting_code NULL (semua bundle manual) tidak ikut.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_bundles_cutting_code' AND object_id = OBJECT_ID('dbo.bundles'))
    CREATE UNIQUE INDEX UX_bundles_cutting_code ON dbo.bundles(article_id, cutting_code)
        WHERE deleted_at IS NULL AND cutting_code IS NOT NULL;
GO

-- Stok cutting & Scan Stok Bundle dibaca lewat index ini.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bundles_cutting_stock' AND object_id = OBJECT_ID('dbo.bundles'))
    CREATE INDEX IX_bundles_cutting_stock ON dbo.bundles(source, stock_status, article_id)
        WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bundles_spread' AND object_id = OBJECT_ID('dbo.bundles'))
    CREATE INDEX IX_bundles_spread ON dbo.bundles(spread_id, bundle_seq) WHERE deleted_at IS NULL;
GO

-- ============ 4. kolom baru di articles ============
-- Target pcs per bundle, dipakai SIS_Cutting_SuggestBundles. Default 50.
IF COL_LENGTH('dbo.articles', 'bundle_target_qty') IS NULL
    ALTER TABLE dbo.articles ADD bundle_target_qty int not null
        constraint DF_articles_bundle_target_qty default 50;
GO

-- ============ 5. verifikasi ============
SELECT 'spreads' AS tabel, COUNT(*) AS baris FROM dbo.spreads
UNION ALL SELECT 'spread_sizes', COUNT(*) FROM dbo.spread_sizes
UNION ALL SELECT 'bundles CUTTING', COUNT(*) FROM dbo.bundles WHERE source = 'CUTTING';
GO
