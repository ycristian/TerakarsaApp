-- Prompt 83: pengambilan data output manual. SELECT saja.
--
--   SIS_ManualOutput_StationList : daftar untuk tab OUT stasiun (satu divisi).
--   SIS_ManualOutput_List        : daftar untuk halaman admin "Output Manual".
--
-- Keduanya hanya membaca manual_outputs + lock-nya. TIDAK ada saldo bundle yang dihitung
-- di sini -- output manual memang tidak menyentuh saldo bundle sama sekali.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ===========================================================================
-- SIS_ManualOutput_StationList
--
-- Dipakai checklist lock di tab OUT, jadi bentuknya mengikuti kebutuhan di sana:
-- baris BELUM lock (bisa dipilih untuk di-lock) dan baris SUDAH lock (ditampilkan
-- dengan gembok + kode periode). Jendela @DaysBack default 90 hari -- sama dengan
-- filter tanggal tab OUT sejak Prompt 56.
--
-- alter_86: @OutputDate = tanggal yang sedang dipilih di filter "Tanggal Kirim" tab OUT.
-- Diisi -> HANYA baris bertanggal itu (kartu Output Manual ikut berpindah tanggal seperti
-- kartu artikel di sebelahnya). NULL -> perilaku lama (semua, dibatasi @DaysBack).
--
-- PENGAMAN: baris BELUM lock di tanggal lain jadi tidak terlihat dari tanggal ini. Itu
-- sengaja dikompensasi di SIS_Station_UnlockedDates, yang sejak alter_86 ikut menghitung
-- manual_outputs -- jadi tanggalnya tetap muncul sebagai chip "Belum lock" dan tunggakan
-- tidak bisa hilang diam-diam. Kalau salah satu dari keduanya diubah, ubah yang lain juga.
--
-- @ResourceId (2026-11-02): Line sesi stasiun. Prompt 83 sengaja TIDAK menyaring per resource
-- -- akibatnya tiap operator sedivisi melihat baris milik operator lain (mis. baris Line A3
-- tampil di sesi Line A5) dan bisa mengunci upah orang lain. Sekarang disaring, selaras dengan
-- baris log di kartu sebelahnya (@ResourceId di SIS_Station_PendingHandover).
-- Pola IS NULL-nya DIBUAT SAMA dengan SP itu: baris tanpa resource tetap ikut, supaya baris
-- data lama/manual tidak terkunci dari semua layar.
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_ManualOutput_StationList
    @DivisionId INT,
    @DaysBack   INT = 90,
    @OutputDate DATE = NULL,
    @ResourceId INT = NULL      -- NULL = semua Line (admin/laporan)
AS
BEGIN
    SET NOCOUNT ON;

    IF @DivisionId IS NULL
    BEGIN
        RAISERROR('Divisi tidak dikenal.', 16, 1);
        RETURN;
    END

    IF ISNULL(@DaysBack, 0) <= 0 SET @DaysBack = 90;

    DECLARE @Since DATETIME2 = DATEADD(DAY, -@DaysBack, SYSDATETIME());

    SELECT mo.manual_output_id AS ManualOutputId,
           mo.resource_id      AS ResourceId,
           res.resource_name   AS ResourceName,
           mo.article_id       AS ArticleId,
           a.article_name      AS ArticleName,
           p.no_po             AS NoPo,
           mo.output_date      AS OutputDate,
           mo.work_description AS WorkDescription,
           mo.size_name        AS SizeName,
           mo.qty              AS Qty,
           mo.reject_qty       AS RejectQty,
           mo.note             AS Note,
           mo.created_at       AS CreatedAt,
           CAST(CASE WHEN mo.lock_id IS NULL THEN 0 ELSE 1 END AS BIT) AS IsLocked,
           pp.period_code      AS LockPeriodCode,
           -- Badge "Potongan" di UI stasiun.
           CAST(CASE WHEN mo.qty < 0 THEN 1 ELSE 0 END AS BIT) AS IsPotongan
    FROM manual_outputs mo
    LEFT JOIN resources res ON res.resource_id = mo.resource_id
    LEFT JOIN articles a ON a.article_id = mo.article_id
    LEFT JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN workflow_locks wl ON wl.lock_id = mo.lock_id
    LEFT JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
    WHERE mo.deleted_at IS NULL
      AND mo.division_id = @DivisionId
      -- alter_86: kalau tanggal dikirim, DIA yang menentukan isi kartu -- termasuk untuk
      -- baris belum lock. Tunggakannya tetap terjaga lewat chip "Belum lock" (lihat
      -- catatan di header SP ini).
      AND (@OutputDate IS NULL OR mo.output_date = @OutputDate)
      -- Jalur @OutputDate NULL (perilaku lama): baris belum lock SELALU ikut walau tua,
      -- kalau tidak, tunggakan lock bisa hilang dari layar tanpa pernah dibereskan.
      -- Jendela ini diukur dari created_at (kapan barisnya dicatat), bukan output_date.
      AND (@OutputDate IS NOT NULL OR mo.lock_id IS NULL OR mo.created_at >= @Since)
      AND (@ResourceId IS NULL OR mo.resource_id IS NULL OR mo.resource_id = @ResourceId)
    ORDER BY mo.output_date DESC, mo.created_at DESC, mo.manual_output_id DESC;
END;
GO

-- ===========================================================================
-- SIS_ManualOutput_List -- halaman admin.
--
-- Filter (semua opsional, saling bebas):
--   @OnlyUnlinked = 1  -> hanya baris yang BELUM terhubung artikel (article_id IS NULL)
--   @DivisionId        -> divisi pencatat
--   @PayrollPeriodId   -> periode gajian baris itu, yaitu lock_id -> workflow_locks
--                         .payroll_period_id. Baris yang BELUM lock tidak punya periode,
--                         jadi tidak pernah ikut kalau filter ini dipakai.
--   @ResourceId        -> pemilik upah
--   @Search            -> cocok di deskripsi kerjaan / catatan / nama artikel
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_ManualOutput_List
    @OnlyUnlinked    BIT = 0,
    @DivisionId      INT = NULL,
    @PayrollPeriodId INT = NULL,
    @ResourceId      INT = NULL,
    @Search          NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search, N''))), N'');

    SELECT mo.manual_output_id AS ManualOutputId,
           mo.resource_id      AS ResourceId,
           res.resource_name   AS ResourceName,
           mo.division_id      AS DivisionId,
           d.division_name     AS DivisionName,
           mo.article_id       AS ArticleId,
           a.article_name      AS ArticleName,
           p.no_po             AS NoPo,
           p.project_name      AS ProjectName,
           mo.output_date      AS OutputDate,
           mo.work_description AS WorkDescription,
           mo.size_name        AS SizeName,
           mo.qty              AS Qty,
           mo.reject_qty       AS RejectQty,
           mo.note             AS Note,
           mo.created_at       AS CreatedAt,
           mo.lock_id          AS LockId,
           CAST(CASE WHEN mo.lock_id IS NULL THEN 0 ELSE 1 END AS BIT) AS IsLocked,
           pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code       AS PeriodCode,
           CAST(CASE WHEN pp.finalized_at IS NULL THEN 0 ELSE 1 END AS BIT) AS IsPeriodFinalized,
           CAST(CASE WHEN mo.qty < 0 THEN 1 ELSE 0 END AS BIT) AS IsPotongan,
           -- Harga yang dibekukan untuk baris ini (kalau sudah lock). Ditampilkan
           -- read-only di halaman Output Manual -- koreksinya di Rekap Gajian.
           wli.lock_item_id AS LockItemId,
           wli.unit_price   AS UnitPrice
    FROM manual_outputs mo
    LEFT JOIN resources res ON res.resource_id = mo.resource_id
    LEFT JOIN divisions d ON d.division_id = mo.division_id
    LEFT JOIN articles a ON a.article_id = mo.article_id
    LEFT JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN workflow_locks wl ON wl.lock_id = mo.lock_id AND wl.deleted_at IS NULL
    LEFT JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
    LEFT JOIN workflow_lock_items wli ON wli.manual_output_id = mo.manual_output_id
                                     AND wli.released_at IS NULL AND wli.deleted_at IS NULL
    WHERE mo.deleted_at IS NULL
      AND (@OnlyUnlinked = 0 OR mo.article_id IS NULL)
      AND (@DivisionId IS NULL OR mo.division_id = @DivisionId)
      AND (@ResourceId IS NULL OR mo.resource_id = @ResourceId)
      AND (@PayrollPeriodId IS NULL OR wl.payroll_period_id = @PayrollPeriodId)
      AND (@Search IS NULL
           OR mo.work_description LIKE '%' + @Search + '%'
           OR mo.note LIKE '%' + @Search + '%'
           OR a.article_name LIKE '%' + @Search + '%')
    ORDER BY mo.output_date DESC, mo.created_at DESC, mo.manual_output_id DESC;
END;
GO
