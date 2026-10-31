-- Prompt 83: output manual (manual_outputs) + harga borongan dibekukan saat lock
-- (workflow_lock_items.unit_price) + finalisasi periode gajian.
-- Idempotent -- aman dijalankan berkali-kali.
-- Jalankan SETELAH sql/alter_55_workflow_lock.sql dan sql/prompt_59_harga_rekap_nonpo.sql.
--
-- -------------------------------------------------------------------------------
-- CATATAN PENTING soal master tarif
-- Prompt 83 menyebut tabel article_workflow_steps. Tabel itu TIDAK ADA di DB ini --
-- step per artikel bernama article_workflows, dan kolom tarifnya SUDAH ADA sejak
-- Prompt 59: article_workflows.unit_price decimal(19,4) NOT NULL DEFAULT 0. Jadi tidak
-- ada kolom tarif baru yang perlu ditambahkan di sini.
--
-- Karena master tarif itu NOT NULL DEFAULT 0, "tarif tidak ditemukan" tidak bisa
-- dibedakan dari "tarif memang 0" hanya dari nilainya. Keputusan owner:
--     step biasa  unit_price = 0  -> lock item NULL (disorot, blokir finalisasi)
--     step biasa  unit_price > 0  -> lock item = nilai itu
--     step Bundling (is_bundling=1) -> lock item = 0 (0 di sana HARGA YANG BENAR,
--                                      Prompt 59 -- kalau dipetakan ke NULL, tiap
--                                      periode akan macet di baris Bundling)
-- Aturan ini punya SATU definisi: dbo.SIS_fn_StepUnitPrice (sql/sp_ManualOutput_Manage.sql).
--
-- -------------------------------------------------------------------------------
-- CATATAN soal non_po_outputs (Prompt 59)
-- non_po_outputs menampung konsep yang mirip (output di luar PO, masuk upah resource)
-- tapi dengan kebijakan harga TERBALIK: harga diisi sendiri oleh PIC di stasiun.
-- Keputusan owner: non_po_outputs DIRETIRE -- tabel & datanya DIBIARKAN UTUH (rekap
-- lama masih membacanya), hanya form inputnya yang dimatikan di stasiun. Tidak ada
-- migrasi data dari non_po_outputs ke manual_outputs.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- 1. manual_outputs -- output yang tidak lewat bundle, dicatat PIC per divisi.
--
--    TIDAK ADA relasi ke bundle/PO dan TIDAK ADA payroll_period_id: periode gajian
--    baris ini ditentukan oleh lock_id -> workflow_locks.payroll_period_id, sama
--    persis dengan article_workflow_logs (aturan CLAUDE.md "periode gajian log =
--    periode di workflow_locks, bukan dari created_at"). Ini yang membedakannya dari
--    non_po_outputs, yang menyimpan periodenya sendiri dari output_at.
--
--    qty BOLEH 0 ATAU MINUS. Baris qty minus = CATATAN POTONGAN: PIC menulis
--    kronologi + usulan potongan di note, nominalnya ditentukan admin produksi
--    lewat unit_price di lock item.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'manual_outputs')
BEGIN
    CREATE TABLE manual_outputs(
        manual_output_id int primary key identity(1,1),
        resource_id int not null                   -- operator/line yang mengerjakan (pemilik upah)
            constraint FK_mo_resources foreign key references resources(resource_id),
        division_id int not null                   -- divisi stasiun; disalin SP dari resources
            constraint FK_mo_divisions foreign key references divisions(division_id),
        article_id int null                         -- OPSIONAL; boleh ditempel admin belakangan,
                                                    -- termasuk ke baris yang sudah lock
            constraint FK_mo_articles foreign key references articles(article_id),
        work_description nvarchar(300) not null,    -- wajib, mis. 'kaos polos hitam pak Budi'
        size_name varchar(50) null,                 -- teks bebas (BUKAN FK ke size_pack_details);
                                                    -- dinamai *_name mengikuti konvensi proyek
        qty int not null default 0,                 -- boleh 0 atau minus (lihat catatan di atas)
        reject_qty int not null default 0,
        note nvarchar(500) null,
        lock_id int null                            -- Prompt 55/83: lock yang SEDANG berlaku.
                                                    -- Terisi = qty beku di semua jalur.
            constraint FK_mo_workflow_locks foreign key references workflow_locks(lock_id),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,                    -- user sistem station_system (tabel Users).
                                                    -- TANPA FK, mengikuti tabel lain di DB ini
                                                    -- (non_po_outputs, workflow_locks, dst).
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_mo_division_lock')
    CREATE INDEX IX_mo_division_lock ON manual_outputs(division_id, lock_id)
        INCLUDE (resource_id, article_id, qty) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_mo_lock_id')
    CREATE INDEX IX_mo_lock_id ON manual_outputs(lock_id) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_mo_article_id')
    CREATE INDEX IX_mo_article_id ON manual_outputs(article_id) WHERE deleted_at IS NULL;
GO

-- ---------------------------------------------------------------------------
-- 2. workflow_lock_items: baris lock sekarang bisa berasal dari DUA sumber.
--
--    workflow_log_id harus jadi NULLABLE. Itu memaksa UX_wli_log_active dibongkar:
--    index UNIQUE memperlakukan NULL sebagai nilai yang SAMA, jadi tanpa penambahan
--    filter "workflow_log_id IS NOT NULL" hanya SATU baris MANUAL yang boleh aktif
--    di seluruh tabel. Tidak ada recreate table di sini (cuma drop index + ALTER
--    COLUMN + create index), jadi tidak perlu penampungan data.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_lock_items') AND name = 'source'
)
    ALTER TABLE workflow_lock_items
        ADD source varchar(10) not null constraint DF_wli_source default 'LOG';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_lock_items') AND name = 'manual_output_id'
)
    ALTER TABLE workflow_lock_items
        ADD manual_output_id int null
            constraint FK_wli_manual_outputs foreign key references manual_outputs(manual_output_id);
GO

-- Harga borongan yang DIBEKUKAN saat lock. NULL = tarif belum diketahui; admin produksi
-- mengisinya di Rekap Gajian selama periode belum final. Sengaja NULLABLE: 0 adalah harga
-- yang sah (step Bundling), jadi 0 tidak boleh dipakai sebagai penanda "belum diisi".
-- Lock item LAMA (sebelum prompt ini) dibiarkan NULL -- di luar cakupan Prompt 83.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_lock_items') AND name = 'unit_price'
)
    ALTER TABLE workflow_lock_items
        ADD unit_price decimal(19,4) null;
GO

-- workflow_log_id -> NULLABLE (hanya kalau masih NOT NULL).
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_lock_items') AND name = 'workflow_log_id'
      AND is_nullable = 0
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_wli_log_active'
                 AND object_id = OBJECT_ID('workflow_lock_items'))
        DROP INDEX UX_wli_log_active ON workflow_lock_items;

    ALTER TABLE workflow_lock_items ALTER COLUMN workflow_log_id int NULL;
END
GO

-- Satu baris log hanya boleh punya SATU lock aktif -- sama seperti sebelumnya, cuma
-- ditambah filter workflow_log_id IS NOT NULL supaya baris MANUAL tidak saling bentrok.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_wli_log_active'
                 AND object_id = OBJECT_ID('workflow_lock_items'))
    CREATE UNIQUE INDEX UX_wli_log_active ON workflow_lock_items(workflow_log_id)
        WHERE released_at IS NULL AND deleted_at IS NULL AND workflow_log_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_wli_manual_active'
                 AND object_id = OBJECT_ID('workflow_lock_items'))
    CREATE UNIQUE INDEX UX_wli_manual_active ON workflow_lock_items(manual_output_id)
        WHERE released_at IS NULL AND deleted_at IS NULL AND manual_output_id IS NOT NULL;
GO

-- TEPAT SATU dari workflow_log_id / manual_output_id terisi, sesuai source.
-- WITH NOCHECK: baris lock LAMA tidak diverifikasi ulang (semuanya source='LOG' lewat
-- DEFAULT dan workflow_log_id-nya pasti terisi, tapi NOCHECK membuat script tetap aman
-- dijalankan di DB yang datanya sudah banyak).
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_wli_source')
    ALTER TABLE workflow_lock_items WITH NOCHECK
        ADD CONSTRAINT CK_wli_source CHECK (
            (source = 'LOG'    AND workflow_log_id IS NOT NULL AND manual_output_id IS NULL)
         OR (source = 'MANUAL' AND manual_output_id IS NOT NULL AND workflow_log_id IS NULL)
        );
GO

-- ---------------------------------------------------------------------------
-- 3. payroll_periods: tidak ada kolom baru -- finalized_at/finalized_by sudah ada
--    sejak Prompt 55, cuma belum pernah ada SP yang MENGISINYA. Lihat
--    SIS_PayrollPeriod_Manage @Action='FINALIZE'/'UNFINALIZE' di
--    sql/sp_PayrollPeriod_Manage.sql.
-- ---------------------------------------------------------------------------
GO
