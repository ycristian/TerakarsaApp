-- Migrasi untuk DB yang sudah ada: modul Packing (karung) -- tabel packs/pack_items +
-- kolom enable_packing di stations. Idempotent, aman dijalankan berulang.
-- SP terkait ada di sp_Pack_Manage.sql / sp_Pack_Select.sql (dijalankan terpisah).

IF OBJECT_ID('packs', 'U') IS NULL
BEGIN
    CREATE TABLE packs(
     pack_id int primary key identity(1,1),
     project_id int not null
       constraint FK_packs_projects foreign key references projects(project_id),
     pack_no int not null,                      -- urut per project, termasuk soft-deleted
     serial varchar(20) not null,               -- PK{yy}-{6 digit global}
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     delete_reason varchar(255) null
    );
END
GO

IF OBJECT_ID('pack_items', 'U') IS NULL
BEGIN
    CREATE TABLE pack_items(
     pack_item_id int primary key identity(1,1),
     pack_id int not null
       constraint FK_pack_items_packs foreign key references packs(pack_id),
     article_id int not null
       constraint FK_pack_items_articles foreign key references articles(article_id),
     article_size_id int not null
       constraint FK_pack_items_sizes foreign key references article_sizes(article_size_id),
     qty_plan int not null,
     qty_actual int null,                       -- NULL = belum dikonfirmasi
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_packs_serial' AND object_id = OBJECT_ID('packs'))
    CREATE UNIQUE INDEX UX_packs_serial ON packs(serial) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_packs_project' AND object_id = OBJECT_ID('packs'))
    CREATE INDEX IX_packs_project ON packs(project_id) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pack_items_pack' AND object_id = OBJECT_ID('pack_items'))
    CREATE INDEX IX_pack_items_pack ON pack_items(pack_id) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('stations') AND name = 'enable_packing'
)
BEGIN
    ALTER TABLE stations ADD enable_packing bit not null default 0;
END
GO
