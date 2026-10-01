-- Prompt 55: lock baris article_workflow_logs + periode gajian sebagai baris tabel.
-- Idempotent -- aman dijalankan berkali-kali / terhadap DB yang belum atau sudah punya
-- sebagian dari perubahan ini.
--
-- Konsep: baris log yang belum di-lock boleh diubah/dihapus kapan pun (asal saldo tidak
-- jadi minus), baris yang sudah di-lock tidak bisa diubah lewat jalur apa pun -- termasuk
-- SIS_SuperAdmin_Manage. Pelepasan lock HANYA lewat unlock_requests yang disetujui admin.
-- Tidak ada kolom status di tabel mana pun -- keadaan diturunkan dari timestamp
-- (finalized_at, released_at, approved_at/rejected_at, deleted_at).
--
-- Urutan CREATE mengikuti arah FK: payroll_periods -> workflow_locks -> unlock_requests
-- -> workflow_lock_items (menunjuk keduanya) -> unlock_request_items.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- a. payroll_periods -- periode gajian (Sabtu 10:00, rumus Prompt 30) jadi baris.
--    Penomoran: periode ke-N tahun Y BERAKHIR di Sabtu ke-N tahun itu jam 10:00,
--    period_start = period_end - 7 hari. Lihat SIS_PayrollPeriod_Manage GENERATE_YEAR
--    di sql/sp_PayrollPeriod_Manage.sql -- jangan mengisi tabel ini dengan tangan.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'payroll_periods')
BEGIN
    CREATE TABLE payroll_periods(
        payroll_period_id int primary key identity(1,1),
        period_year smallint not null,
        period_no tinyint not null,             -- 1..52/53 (jumlah Sabtu di tahun itu)
        period_code varchar(10) not null,       -- 'YY-wNN', mis. '26-w40' -- nomor periode internal, bukan ISO week
        period_start datetime2 not null,        -- inklusif
        period_end datetime2 not null,          -- eksklusif
        finalized_at datetime2 null,            -- disiapkan, belum ada UI finalisasi
        finalized_by int null,
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_payroll_periods_year_no')
    CREATE UNIQUE INDEX UX_payroll_periods_year_no ON payroll_periods(period_year, period_no) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_payroll_periods_code')
    CREATE UNIQUE INDEX UX_payroll_periods_code ON payroll_periods(period_code) WHERE deleted_at IS NULL;
GO

-- ---------------------------------------------------------------------------
-- b. workflow_locks -- header satu kali tekan Lock di stasiun (atau lock sistem go-live).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'workflow_locks')
BEGIN
    CREATE TABLE workflow_locks(
        lock_id int primary key identity(1,1),
        division_id int not null                -- divisi pemilik baris OUT yang di-lock
            constraint FK_wl_divisions foreign key references divisions(division_id),
        station_id int null                     -- NULL untuk lock sistem (go-live)
            constraint FK_wl_stations foreign key references stations(station_id),
        payroll_period_id int not null          -- dipilih PIC saat menekan Lock
            constraint FK_wl_payroll_periods foreign key references payroll_periods(payroll_period_id),
        locked_by_resource_id int null          -- operator sesi stasiun
            constraint FK_wl_resources foreign key references resources(resource_id),
        locked_by_name varchar(150) null,       -- hanya lock sistem ('SYSTEM - GO LIVE');
                                                 -- nanti dipakai identitas kartu NFC
        locked_at datetime2 not null default sysdatetime(),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

-- ---------------------------------------------------------------------------
-- e. unlock_requests -- pengajuan buka lock dari stasiun, disetujui/ditolak admin.
--    Keadaan menunggu = approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL.
--    Pembatalan oleh pengaju = soft delete.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'unlock_requests')
BEGIN
    CREATE TABLE unlock_requests(
        request_id int primary key identity(1,1),
        division_id int not null
            constraint FK_ur_divisions foreign key references divisions(division_id),
        station_id int null
            constraint FK_ur_stations foreign key references stations(station_id),
        reason varchar(500) not null,           -- wajib, minimal 5 karakter
        requested_by_resource_id int null       -- operator sesi stasiun
            constraint FK_ur_resources foreign key references resources(resource_id),
        approved_at datetime2 null,
        approved_by int null,
        rejected_at datetime2 null,
        rejected_by int null,
        admin_note varchar(500) null,           -- wajib saat REJECT
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

-- ---------------------------------------------------------------------------
-- c. workflow_lock_items -- isi lock + riwayat. Lock yang sudah dilepas TIDAK dihapus
--    (released_at terisi), supaya jejak "pernah di-lock periode mana" tetap ada.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'workflow_lock_items')
BEGIN
    CREATE TABLE workflow_lock_items(
        lock_item_id int primary key identity(1,1),
        lock_id int not null
            constraint FK_wli_workflow_locks foreign key references workflow_locks(lock_id),
        workflow_log_id int not null
            constraint FK_wli_article_workflow_logs foreign key references article_workflow_logs(workflow_log_id),
        -- Snapshot nilai baris saat di-lock (bukti isi periode gajian tidak berubah diam-diam).
        snap_qty_ok int not null default 0,
        snap_qty_reject_print int not null default 0,
        snap_qty_reject_fabric int not null default 0,
        snap_qty_reject_sewing int not null default 0,
        snap_qty_reject_rework int not null default 0,
        snap_qty_lost int not null default 0,
        snap_article_size_id int null,
        snap_resource_id int null,
        snap_target_division_id int null,
        released_at datetime2 null,             -- terisi saat lock dilepas oleh request yang disetujui
        released_by_request_id int null
            constraint FK_wli_unlock_requests foreign key references unlock_requests(request_id),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

-- Satu baris log maksimal punya SATU lock aktif.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_wli_log_active')
    CREATE UNIQUE INDEX UX_wli_log_active ON workflow_lock_items(workflow_log_id)
        WHERE released_at IS NULL AND deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_wli_lock_id')
    CREATE INDEX IX_wli_lock_id ON workflow_lock_items(lock_id) WHERE deleted_at IS NULL;
GO

-- ---------------------------------------------------------------------------
-- f. unlock_request_items -- baris log yang diminta dibuka + lock aktif yang jadi sasaran.
--    Tanpa updated_*/deleted_* (ikut nasib header, pola tabel detail satu arah).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'unlock_request_items')
BEGIN
    CREATE TABLE unlock_request_items(
        request_item_id int primary key identity(1,1),
        request_id int not null
            constraint FK_uri_unlock_requests foreign key references unlock_requests(request_id),
        workflow_log_id int not null
            constraint FK_uri_article_workflow_logs foreign key references article_workflow_logs(workflow_log_id),
        lock_item_id int not null               -- lock aktif yang diminta dilepas
            constraint FK_uri_workflow_lock_items foreign key references workflow_lock_items(lock_item_id),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_uri_request_id')
    CREATE INDEX IX_uri_request_id ON unlock_request_items(request_id);
GO

-- ---------------------------------------------------------------------------
-- d. article_workflow_logs.lock_id -- lock yang SEDANG berlaku untuk baris ini.
--    NULL = bebas diedit. Periode gajian sebuah log diturunkan dari
--    lock_id -> workflow_locks.payroll_period_id -- TIDAK ada kolom periode di log.
-- ---------------------------------------------------------------------------
IF COL_LENGTH('article_workflow_logs', 'lock_id') IS NULL
    ALTER TABLE article_workflow_logs ADD lock_id int null;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_awl_workflow_locks')
    ALTER TABLE article_workflow_logs ADD CONSTRAINT FK_awl_workflow_locks
        FOREIGN KEY (lock_id) REFERENCES workflow_locks(lock_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_lock_id')
    CREATE INDEX IX_awl_lock_id ON article_workflow_logs(lock_id) WHERE deleted_at IS NULL;
GO
