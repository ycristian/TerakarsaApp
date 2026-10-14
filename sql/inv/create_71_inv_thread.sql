/* =============================================================
   TMOS - Module Stok Benang (Prompt 71-77) - Skema `inv`
   FILE CANONICAL untuk seluruh tabel & view schema inv.
   Tabel schema dbo TIDAK disentuh dari file ini
   (sql/create_tables_tmos_final.sql tetap canonical untuk dbo).

   Aturan penulisan mengikuti sql/create_tables_tmos_final.sql dan
   sql/tni/create_schema_tni.sql:
   1. snake_case; varchar (bukan nvarchar)
   2. Kolom wajib bisnis = NOT NULL (name, code, FK utama)
   3. Semua FK diberi nama (FK_anak_induk) agar mudah di-ALTER
   4. Kode unik via filtered unique index WHERE deleted_at IS NULL
      (kode bisa dipakai ulang setelah baris lama di-soft-delete)
   5. created_by/updated_by/deleted_by: int tanpa FK -- sama dengan
      tabel dbo (aturan 9 di file canonical dbo)
   6. TIDAK ADA kolom saldo yang berdiri sendiri: saldo whole ada di
      inv.thread_stocks dan HANYA boleh diubah SP movement (Prompt 72);
      ringkasan per SKU diturunkan di inv.v_thread_item_stock.

   Idempotent: tiap objek dibungkus IF ... IS NULL / NOT EXISTS,
   view & SP pakai CREATE OR ALTER.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inv')
    EXEC('CREATE SCHEMA inv');
GO

-- ============ 1. MASTER PENDUKUNG ============

-- Jenis benang: POLY / COTTON / SPUN / NYLON (di-seed, lihat seed_71_inv_thread.sql).
IF OBJECT_ID('inv.thread_types','U') IS NULL
CREATE TABLE inv.thread_types(
 thread_type_id int primary key identity(1,1),
 code varchar(20) not null,                 -- 3 huruf pertama ikut jadi bagian sku_code
 name varchar(50) not null,
 sort_order int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

IF OBJECT_ID('inv.thread_brands','U') IS NULL
CREATE TABLE inv.thread_brands(
 thread_brand_id int primary key identity(1,1),
 name varchar(100) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Rak / lokasi penyimpanan: A1, B5, X12. Tidak di-seed -- dibuat dari halaman master.
IF OBJECT_ID('inv.thread_locations','U') IS NULL
CREATE TABLE inv.thread_locations(
 thread_location_id int primary key identity(1,1),
 code varchar(20) not null,
 name varchar(100) null,
 sort_order int not null default 0,
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Kategori alasan ADJUST (stock opname, Prompt 74). PK = code (bukan identity):
-- kode alasan ikut tersimpan di inv.thread_movements.reason_code.
IF OBJECT_ID('inv.thread_reason_codes','U') IS NULL
CREATE TABLE inv.thread_reason_codes(
 code varchar(30) not null primary key,
 name varchar(100) not null,
 requires_note bit not null default 0,
 sort_order int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 2. SKU BENANG ============

-- Satu baris = satu SKU: jenis + merk + warna + jenis kones. Kones whole TIDAK
-- dicatat satu-satu; labelnya sama untuk seluruh kones SKU ini (QR `TB:<sku_code>`).
IF OBJECT_ID('inv.thread_items','U') IS NULL
CREATE TABLE inv.thread_items(
 thread_item_id int primary key identity(1,1),
 sku_code varchar(40) not null,             -- DIBUAT SISTEM: BN-<TYPE3>-<BRAND3>-<kode warna>-<K|B>
 thread_type_id int not null
   constraint FK_inv_thread_items_types foreign key references inv.thread_types(thread_type_id),
 thread_brand_id int not null
   constraint FK_inv_thread_items_brands foreign key references inv.thread_brands(thread_brand_id),
 color_name varchar(100) not null,
 color_code varchar(30) not null,
 cone_size varchar(10) not null
   constraint CK_inv_thread_items_cone_size check (cone_size in ('KECIL','BESAR')),
 photo_path varchar(255) null,              -- path relatif FileStorage; nama file GUID di disk
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Saldo kones WHOLE per SKU per rak. HANYA diubah oleh SP movement (Prompt 72) --
-- jangan pernah di-UPDATE dari API/halaman.
IF OBJECT_ID('inv.thread_stocks','U') IS NULL
CREATE TABLE inv.thread_stocks(
 thread_stock_id int primary key identity(1,1),
 thread_item_id int not null
   constraint FK_inv_thread_stocks_items foreign key references inv.thread_items(thread_item_id),
 thread_location_id int not null
   constraint FK_inv_thread_stocks_locations foreign key references inv.thread_locations(thread_location_id),
 qty_whole int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Kones SPLIT = kones bekas pakai yang kembali dari line. Satu baris per kones fisik,
-- berat NETTO gram (tanpa tube), punya label sendiri (QR `TS:<cone_code>`).
IF OBJECT_ID('inv.thread_split_cones','U') IS NULL
CREATE TABLE inv.thread_split_cones(
 thread_split_cone_id int primary key identity(1,1),
 cone_code varchar(20) not null,            -- SP-000001, serial GLOBAL (applock 'thread_split_seq')
 thread_item_id int not null
   constraint FK_inv_thread_split_cones_items foreign key references inv.thread_items(thread_item_id),
 weight_gram int not null,
 thread_location_id int null                -- NULL saat status ISSUED (sedang di line)
   constraint FK_inv_thread_split_cones_locations foreign key references inv.thread_locations(thread_location_id),
 [status] varchar(10) not null
   constraint CK_inv_thread_split_cones_status check ([status] in ('IN_STOCK','ISSUED','EMPTY')),
 issued_to_resource_id int null
   constraint FK_inv_thread_split_cones_resources foreign key references dbo.resources(resource_id),
 issued_project_id int null
   constraint FK_inv_thread_split_cones_projects foreign key references dbo.projects(project_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 3. MOVEMENT ============

-- Satu baris = satu mutasi. Stok sistem = hasil catatan di tabel ini; stock opname
-- TIDAK menimpa stok, menyamakannya = movement ADJUST* yang menunjuk baris opname.
IF OBJECT_ID('inv.thread_movements','U') IS NULL
CREATE TABLE inv.thread_movements(
 thread_movement_id int primary key identity(1,1),
 movement_type varchar(20) not null
   constraint CK_inv_thread_movements_type check (movement_type in
     ('RECEIVE','ISSUE','RETURN','ISSUE_SPLIT','RETURN_SPLIT','MOVE','MOVE_SPLIT',
      'ADJUST','ADJUST_SPLIT','EMPTY')),
 thread_item_id int not null
   constraint FK_inv_thread_movements_items foreign key references inv.thread_items(thread_item_id),
 thread_split_cone_id int null
   constraint FK_inv_thread_movements_split_cones foreign key references inv.thread_split_cones(thread_split_cone_id),
 from_location_id int null
   constraint FK_inv_thread_movements_from_locations foreign key references inv.thread_locations(thread_location_id),
 to_location_id int null
   constraint FK_inv_thread_movements_to_locations foreign key references inv.thread_locations(thread_location_id),
 qty_whole int null,                        -- + / - ; untuk tipe whole
 weight_gram int null,                      -- untuk tipe split (berat saat mutasi itu)
 resource_id int null                       -- line tujuan/asal
   constraint FK_inv_thread_movements_resources foreign key references dbo.resources(resource_id),
 project_id int null
   constraint FK_inv_thread_movements_projects foreign key references dbo.projects(project_id),
 reason_code varchar(30) null               -- hanya ADJUST / ADJUST_SPLIT
   constraint FK_inv_thread_movements_reason_codes foreign key references inv.thread_reason_codes(code),
 note varchar(500) null,
 opname_line_id int null,                   -- FK ke inv.thread_opname_lines ditambah di Prompt 74
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 4. INDEX ============

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_types_code')
CREATE UNIQUE INDEX UX_inv_thread_types_code
    ON inv.thread_types(code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_brands_name')
CREATE UNIQUE INDEX UX_inv_thread_brands_name
    ON inv.thread_brands(name) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_locations_code')
CREATE UNIQUE INDEX UX_inv_thread_locations_code
    ON inv.thread_locations(code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_items_sku_code')
CREATE UNIQUE INDEX UX_inv_thread_items_sku_code
    ON inv.thread_items(sku_code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_stocks_item_location')
CREATE UNIQUE INDEX UX_inv_thread_stocks_item_location
    ON inv.thread_stocks(thread_item_id, thread_location_id) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_thread_split_cones_code')
CREATE UNIQUE INDEX UX_inv_thread_split_cones_code
    ON inv.thread_split_cones(cone_code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_thread_split_cones_item_status')
CREATE INDEX IX_thread_split_cones_item_status
    ON inv.thread_split_cones(thread_item_id, [status]) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_thread_movements_item_date')
CREATE INDEX IX_thread_movements_item_date
    ON inv.thread_movements(thread_item_id, created_at) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_thread_movements_type_date')
CREATE INDEX IX_thread_movements_type_date
    ON inv.thread_movements(movement_type, created_at) WHERE deleted_at IS NULL;
GO

-- ============ 5. VIEW RINGKASAN STOK PER SKU ============

-- Satu baris per SKU hidup. Dipakai daftar SKU, detail SKU, hasil scan, dan opname.
-- LocationCodes = kode rak yang qty_whole > 0, diurutkan sort_order lalu code.
CREATE OR ALTER VIEW inv.v_thread_item_stock
AS
SELECT i.thread_item_id,
       ISNULL(w.qty_whole_total, 0)      AS qty_whole_total,
       ISNULL(s.split_count_in_stock, 0) AS split_count_in_stock,
       ISNULL(s.split_gram_in_stock, 0)  AS split_gram_in_stock,
       ISNULL(s.split_count_issued, 0)   AS split_count_issued,
       ISNULL(s.split_gram_issued, 0)    AS split_gram_issued,
       w.location_codes
FROM inv.thread_items i
OUTER APPLY (
    SELECT SUM(st.qty_whole) AS qty_whole_total,
           STRING_AGG(CASE WHEN st.qty_whole > 0 THEN l.code END, ' / ')
               WITHIN GROUP (ORDER BY l.sort_order, l.code) AS location_codes
    FROM inv.thread_stocks st
    INNER JOIN inv.thread_locations l ON l.thread_location_id = st.thread_location_id
    WHERE st.thread_item_id = i.thread_item_id
      AND st.deleted_at IS NULL
      AND l.deleted_at IS NULL
) w
OUTER APPLY (
    SELECT SUM(CASE WHEN c.[status] = 'IN_STOCK' THEN 1 ELSE 0 END)             AS split_count_in_stock,
           SUM(CASE WHEN c.[status] = 'IN_STOCK' THEN c.weight_gram ELSE 0 END) AS split_gram_in_stock,
           SUM(CASE WHEN c.[status] = 'ISSUED'   THEN 1 ELSE 0 END)             AS split_count_issued,
           SUM(CASE WHEN c.[status] = 'ISSUED'   THEN c.weight_gram ELSE 0 END) AS split_gram_issued
    FROM inv.thread_split_cones c
    WHERE c.thread_item_id = i.thread_item_id
      AND c.deleted_at IS NULL
      AND c.[status] <> 'EMPTY'
) s
WHERE i.deleted_at IS NULL;
GO
