-- Prompt 59: harga per workflow step + tabel output non-PO.
-- Idempotent -- aman dijalankan berkali-kali / terhadap DB yang sudah punya sebagian
-- perubahan ini. Jalankan SETELAH sql/alter_55_workflow_lock.sql (payroll_periods dipakai
-- sebagai FK di bawah).
--
-- Konsep harga: harga melekat pada STEP, bukan pada baris log. workflow_template_steps
-- menyimpan harga ARAHAN AWAL, article_workflows menyimpan harga yang BERLAKU untuk artikel
-- itu (disalin saat APPLY, lalu bebas diubah per artikel). Rekap produksi SELALU membaca
-- article_workflows.unit_price yang berlaku SEKARANG -- tidak ada snapshot harga di
-- article_workflow_logs maupun workflow_lock_items (pencatatan nilai per periode menyusul
-- lewat settlement payroll di prompt lain).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- a. Harga step. decimal(19,4) -- 4 desimal supaya harga satuan hasil pembagian
--    (mis. borongan per lusin dibagi 12) tidak dibulatkan diam-diam.
--    Data lama otomatis 0 lewat DEFAULT pada ALTER (NOT NULL + default = kolom terisi 0
--    untuk semua baris yang sudah ada, tanpa perlu UPDATE terpisah).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_template_steps') AND name = 'unit_price'
)
    ALTER TABLE workflow_template_steps
        ADD unit_price decimal(19,4) not null constraint DF_wts_unit_price default 0;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('article_workflows') AND name = 'unit_price'
)
    ALTER TABLE article_workflows
        ADD unit_price decimal(19,4) not null constraint DF_aw_unit_price default 0;
GO

-- ---------------------------------------------------------------------------
-- b. non_po_outputs -- pekerjaan di luar PO/bundle yang diinput PIC dari stasiun
--    (sampel, order toko tanpa PO, dsb). MASUK UPAH resource, jadi punya periode gajian
--    sendiri -- tapi TIDAK ikut mekanisme lock: edit/hapus bebas selama periodenya belum
--    finalized_at (lihat SIS_NonPoOutput_Manage).
--
--    payroll_period_id DISIMPAN (bukan dihitung ulang saat baca) supaya rekap periode
--    cukup satu join; nilainya dihitung ulang oleh SP setiap kali output_at berubah.
--    Tidak ada kolom "jenis" -- keterangan bebas sudah cukup (keputusan prompt).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'non_po_outputs')
BEGIN
    CREATE TABLE non_po_outputs(
        non_po_output_id int primary key identity(1,1),
        resource_id int not null                  -- resource sesi stasiun (pemilik upah)
            constraint FK_npo_resources foreign key references resources(resource_id),
        division_id int not null                  -- divisi resource, disalin SP (bukan dari client)
            constraint FK_npo_divisions foreign key references divisions(division_id),
        payroll_period_id int not null            -- dihitung SP dari output_at (cut-off Sabtu 10:00)
            constraint FK_npo_payroll_periods foreign key references payroll_periods(payroll_period_id),
        output_at datetime2 not null,             -- tanggal + jam pekerjaan; penentu periode
        qty int not null,                         -- > 0 (ditegakkan SP)
        unit_price decimal(19,4) not null,        -- >= 0 (ditegakkan SP)
        remark nvarchar(500) not null,            -- wajib diisi
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,                  -- user sistem station_system
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_npo_resource_period')
    CREATE INDEX IX_npo_resource_period ON non_po_outputs(resource_id, payroll_period_id)
        WHERE deleted_at IS NULL;
GO

-- Verifikasi (tidak ada baris keluar / angka 0 = belum dijalankan).
SELECT
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('workflow_template_steps') AND name = 'unit_price') AS TemplateStepUnitPrice,
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('article_workflows') AND name = 'unit_price') AS ArticleWorkflowUnitPrice,
    (SELECT COUNT(*) FROM sys.tables WHERE name = 'non_po_outputs') AS NonPoOutputsTable,
    (SELECT COUNT(*) FROM sys.indexes WHERE name = 'IX_npo_resource_period') AS NonPoOutputsIndex;
GO
