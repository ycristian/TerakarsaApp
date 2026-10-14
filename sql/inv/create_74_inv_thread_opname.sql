/* =============================================================
   Module Stok Benang (Prompt 74) -- stock opname schema `inv`.
   Lanjutan sql/inv/create_71_inv_thread.sql (canonical tabel inv).

   PRINSIP: stok sistem dan hasil opname DISIMPAN TERPISAH. Tabel di sini
   hanya menyimpan FAKTA FISIK hasil hitung. Opname TIDAK PERNAH menulis
   inv.thread_stocks -- yang mengubah stok hanya movement ADJUST / MOVE yang
   dibuat saat sesi ditutup, dan tiap movement itu menunjuk baris opname-nya
   (inv.thread_movements.opname_line_id) + membawa reason_code.

   Idempotent.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Satu sesi mencakup beberapa rak. Hanya boleh ada SATU sesi OPEN sekaligus
-- (ditegakkan inv.SIS_ThreadOpname_Manage, bukan constraint -- sesi CLOSED tetap
-- tersimpan untuk riwayat).
IF OBJECT_ID('inv.thread_opname_sessions','U') IS NULL
CREATE TABLE inv.thread_opname_sessions(
 thread_opname_session_id int primary key identity(1,1),
 session_no varchar(20) not null,           -- SO26-0001
 [status] varchar(10) not null
   constraint CK_inv_opname_sessions_status check ([status] in ('OPEN','CLOSED')),
 started_at datetime2 not null default sysdatetime(),
 closed_at datetime2 null,
 closed_by int null,
 note varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Rak yang ikut dalam sesi + progresnya.
IF OBJECT_ID('inv.thread_opname_locations','U') IS NULL
CREATE TABLE inv.thread_opname_locations(
 thread_opname_location_id int primary key identity(1,1),
 thread_opname_session_id int not null
   constraint FK_inv_opname_locations_sessions
   foreign key references inv.thread_opname_sessions(thread_opname_session_id),
 thread_location_id int not null
   constraint FK_inv_opname_locations_locations
   foreign key references inv.thread_locations(thread_location_id),
 [status] varchar(10) not null
   constraint CK_inv_opname_locations_status check ([status] in ('PENDING','DRAFT','DONE')),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Satu baris = satu SKU di satu rak. system_qty = SNAPSHOT saldo saat baris dibuat;
-- counted_qty = fakta fisik (NULL = belum dihitung).
IF OBJECT_ID('inv.thread_opname_lines','U') IS NULL
CREATE TABLE inv.thread_opname_lines(
 thread_opname_line_id int primary key identity(1,1),
 thread_opname_session_id int not null
   constraint FK_inv_opname_lines_sessions
   foreign key references inv.thread_opname_sessions(thread_opname_session_id),
 thread_location_id int not null
   constraint FK_inv_opname_lines_locations
   foreign key references inv.thread_locations(thread_location_id),
 thread_item_id int not null
   constraint FK_inv_opname_lines_items
   foreign key references inv.thread_items(thread_item_id),
 system_qty int not null,
 counted_qty int null,
 counted_at datetime2 null,
 counted_by int null,
 split_expected int not null default 0,
 split_found int null,
 resolution varchar(10) null
   constraint CK_inv_opname_lines_resolution check (resolution in ('MOVE','ADJUST','NONE')),
 resolved_movement_id int null
   constraint FK_inv_opname_lines_movements
   foreign key references inv.thread_movements(thread_movement_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Checklist kones split per baris opname: ada / tidak ada di rak itu.
IF OBJECT_ID('inv.thread_opname_splits','U') IS NULL
CREATE TABLE inv.thread_opname_splits(
 thread_opname_split_id int primary key identity(1,1),
 thread_opname_line_id int not null
   constraint FK_inv_opname_splits_lines
   foreign key references inv.thread_opname_lines(thread_opname_line_id),
 thread_split_cone_id int not null
   constraint FK_inv_opname_splits_cones
   foreign key references inv.thread_split_cones(thread_split_cone_id),
 is_found bit null,                         -- NULL = belum dicek
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ INDEX ============

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_opname_sessions_no')
CREATE UNIQUE INDEX UX_inv_opname_sessions_no
    ON inv.thread_opname_sessions(session_no) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_opname_locations_session_loc')
CREATE UNIQUE INDEX UX_inv_opname_locations_session_loc
    ON inv.thread_opname_locations(thread_opname_session_id, thread_location_id)
    WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_opname_lines_session_loc_item')
CREATE UNIQUE INDEX UX_inv_opname_lines_session_loc_item
    ON inv.thread_opname_lines(thread_opname_session_id, thread_location_id, thread_item_id)
    WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_opname_splits_line_cone')
CREATE UNIQUE INDEX UX_inv_opname_splits_line_cone
    ON inv.thread_opname_splits(thread_opname_line_id, thread_split_cone_id)
    WHERE deleted_at IS NULL;
GO

-- ============ FK thread_movements -> opname_lines ============
-- Disiapkan sebagai kolom di Prompt 71, FK-nya baru bisa dipasang sekarang
-- (tabelnya baru ada di file ini).

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_inv_thread_movements_opname_lines')
    ALTER TABLE inv.thread_movements ADD CONSTRAINT FK_inv_thread_movements_opname_lines
        FOREIGN KEY (opname_line_id) REFERENCES inv.thread_opname_lines(thread_opname_line_id);
GO
