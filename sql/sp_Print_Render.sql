-- Prompt 48: perakitan isi cetakan thermal (ESC/POS) pindah dari C# (EscPosBuilder) ke SQL --
-- SP menghasilkan TEKS BER-TOKEN (bukan byte printer), diterjemahkan oleh
-- TerakarsaApp.PrintService/EscPosRenderer.cs saat job diklaim. Revisi layout struk cukup
-- CREATE OR ALTER PROCEDURE di sini, tanpa build/publish ulang service. Kamus token lengkap
-- ada di claude prompt/prompt_48_thermal_token_render.md bagian 2 -- SP di file ini WAJIB
-- patuh persis ke kamus itu (renderer tidak mengenal token di luar kamus, lihat aturan
-- "token tidak dikenal diabaikan").
--
-- Label bundle TSC TTP-244 Pro (TsplBuilder.cs, job_type BUNDLE_LABEL/PACK_LABEL/REJECT_NOTE)
-- TIDAK disentuh sama sekali oleh prompt ini -- jalur RAW_TSPL tetap dirakit C# seperti sekarang.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Potong teks dengan "..." (ASCII, sama pola dengan TsplBuilder.Truncate/EscPosBuilder lama --
-- printer ESC/POS di sini pakai ASCII, bukan unicode ellipsis) bila melebihi @Len. Dipakai SP
-- render kalau perlu memangkas manual di luar mekanisme kolom {2COL}/{ROW} (renderer C#
-- menangani sendiri pemangkasan isi kolom).
CREATE OR ALTER FUNCTION SIS_fn_Trunc(@Text NVARCHAR(MAX), @Len INT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Text IS NULL RETURN NULL;
    IF LEN(@Text) <= @Len RETURN @Text;
    IF @Len <= 3 RETURN LEFT(@Text, @Len);
    RETURN LEFT(@Text, @Len - 3) + N'...';
END;
GO

-- Kamus token pakai kurung kurawal sebagai penanda -- teks dinamis (nama project/artikel/
-- catatan bebas, dst, berasal dari input pengguna) WAJIB di-escape dulu sebelum digabung ke
-- baris token: "{" literal jadi "{{" (lihat kamus token poin 2), dan CR/LF dilucuti supaya satu
-- nilai data tidak diam-diam menjadi beberapa "baris cetak" (kamus: "Satu baris teks = satu
-- baris cetak"). Dipakai semua SP render token, bukan cuma kupon borongan.
CREATE OR ALTER FUNCTION SIS_fn_TokenEscape(@Text NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Text IS NULL RETURN NULL;
    RETURN REPLACE(REPLACE(REPLACE(@Text, N'{', N'{{'), CHAR(13), N' '), CHAR(10), N' ');
END;
GO

-- Muara semua render thermal (job_type -> SP render sesuai routing). Dipanggil API lewat
-- GET api/print/render/{printJobId} SAAT job diklaim (bukan saat dibuat) -- cetak ulang
-- otomatis mengikuti layout & data terkini. Kembalikan satu kolom TokenText NVARCHAR(MAX).
--
-- @DryRun: kalau 1, @PrintJobId dibaca dari print_jobs_dryrun (lihat
-- sql/alter_print_jobs_dryrun.sql), BUKAN print_jobs -- supaya rendering hasil testing tidak
-- pernah bergantung/menyentuh baris live. Routing (print_job_routes/print_devices) TETAP
-- sama untuk keduanya.
CREATE OR ALTER PROCEDURE SIS_Print_Dispatch
    @PrintJobId INT,
    @DryRun     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @JobType VARCHAR(30), @RefId INT, @Payload NVARCHAR(MAX), @PrintDeviceId INT;

    IF @DryRun = 1
        SELECT @JobType = job_type, @RefId = ref_id, @Payload = payload, @PrintDeviceId = print_device_id
        FROM print_jobs_dryrun WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    ELSE
        SELECT @JobType = job_type, @RefId = ref_id, @Payload = payload, @PrintDeviceId = print_device_id
        FROM print_jobs WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;

    IF @JobType IS NULL
    BEGIN
        RAISERROR('Print job %d tidak ditemukan.', 16, 1, @PrintJobId);
        RETURN;
    END

    -- Penjagaan salah-pasang printer: route salah pasang tidak menghasilkan error yang
    -- kelihatan di printer (bukan mode TOKEN = printer akan memuntahkan teks perintah mentah
    -- sebagai kertas) -- gagal jelas di sini jauh lebih baik daripada diam-diam salah.
    DECLARE @RenderMode VARCHAR(20), @PrinterName VARCHAR(255);
    SELECT @RenderMode = render_mode, @PrinterName = printer_name
    FROM print_devices WHERE print_device_id = @PrintDeviceId AND deleted_at IS NULL;

    IF @RenderMode IS NULL OR @RenderMode <> 'TOKEN'
    BEGIN
        -- RAISERROR hanya menerima variabel/literal sebagai argumen substitusi, bukan
        -- ekspresi -- ISNULL() harus ditampung ke variabel dulu.
        DECLARE @PrinterNameSafe VARCHAR(255) = ISNULL(@PrinterName, '(tidak diketahui)');
        RAISERROR('Job %d diarahkan ke printer %s yang bukan mode TOKEN.', 16, 1, @PrintJobId, @PrinterNameSafe);
        RETURN;
    END

    IF @JobType = 'KUPON_BORONGAN'
    BEGIN
        EXEC SIS_Print_KuponBorongan @RefId = @RefId, @Payload = @Payload;
    END
    ELSE
    BEGIN
        RAISERROR('Job type %s belum punya SP render.', 16, 1, @JobType);
        RETURN;
    END
END;
GO

-- Kupon borongan (job_type KUPON_BORONGAN, @RefId = article_workflow_logs.workflow_log_id).
-- Layout SAMA PERSIS dengan cetakan lama (TerakarsaApp.PrintService/EscPosBuilder.
-- BuildKuponBorongan, sebelum prompt ini) -- diterjemahkan elemen per elemen ke token, TIDAK
-- didesain ulang. Data diambil LANGSUNG dari tabel (bukan dari @Payload -- payload lama hanya
-- dipertahankan sebagai parameter untuk kompatibilitas signature, tidak dipakai) supaya cetak
-- ulang mengikuti data terkini. Join sengaja meniru PERSIS @KuponPayload_Create di
-- sql/sp_WorkflowLog_Manage.sql (tanpa filter deleted_at pada tabel yang di-JOIN, konsisten
-- dengan pola pembuatan payload aslinya).
CREATE OR ALTER PROCEDURE SIS_Print_KuponBorongan
    @RefId   INT,
    @Payload NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @WorkflowLogId INT, @Serial VARCHAR(20), @BundleNo INT, @BundleLetter VARCHAR(1),
        @ProjectName NVARCHAR(200), @ArticleName NVARCHAR(200), @BundleRemarks NVARCHAR(500),
        @Style NVARCHAR(100), @Color NVARCHAR(100), @SizeName NVARCHAR(50),
        @QtyOk INT, @QtyRejectPrint INT, @QtyRejectFabric INT, @QtyRejectSewing INT,
        @QtyRejectRework INT, @QtyLost INT, @TailorName NVARCHAR(200), @DivisionName NVARCHAR(150),
        @LineResourceName NVARCHAR(150), @ReceivedAt DATETIME2, @CreatedAt DATETIME2, @UpdatedAt DATETIME2;

    SELECT
        @WorkflowLogId = awl.workflow_log_id,
        @Serial = b.serial,
        @BundleNo = b.bundle_no,
        @BundleLetter = pr.bundle_letter,
        @ProjectName = pr.project_name,
        @ArticleName = a.article_name,
        @BundleRemarks = b.remarks,
        @Style = a.style,
        @Color = a.color,
        @SizeName = spd.size_name,
        @QtyOk = awl.qty_ok,
        @QtyRejectPrint = awl.qty_reject_print,
        @QtyRejectFabric = awl.qty_reject_fabric,
        @QtyRejectSewing = awl.qty_reject_sewing,
        @QtyRejectRework = awl.qty_reject_rework,
        @QtyLost = awl.qty_lost,
        @TailorName = ISNULL(ben.employee_name, ISNULL(brn.resource_name, ISNULL(arn.resource_name, N'-'))),
        @DivisionName = dv.division_name,
        @LineResourceName = lrn.resource_name,
        @ReceivedAt = awl.received_at,
        @CreatedAt = awl.created_at,
        @UpdatedAt = awl.updated_at
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects pr ON pr.project_id = a.project_id
    LEFT JOIN divisions dv ON dv.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources brn ON brn.resource_id = b.resource_id
    LEFT JOIN resources arn ON arn.resource_id = awl.resource_id
    LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
    LEFT JOIN resources lrn ON lrn.resource_id = ben.resource_id
    WHERE awl.workflow_log_id = @RefId;

    IF @WorkflowLogId IS NULL
    BEGIN
        RAISERROR('Log workflow %d tidak ditemukan untuk kupon borongan.', 16, 1, @RefId);
        RETURN;
    END

    DECLARE @NL CHAR(1) = CHAR(10);
    DECLARE @T NVARCHAR(MAX) = N'';

    -- Header: "Coupon {id} - {divisi}" (bold) + separator.
    SET @T += N'{B}Coupon ' + CAST(@WorkflowLogId AS NVARCHAR(20)) + N' - ' + dbo.SIS_fn_TokenEscape(ISNULL(@DivisionName, N'-')) + @NL;
    SET @T += N'{HR}' + @NL;

    -- Serial (bundle no) kiri, size kanan (bold); lalu project/artikel/style-color polos.
    DECLARE @BundleNoText NVARCHAR(30) = CASE WHEN @BundleLetter IS NULL THEN CAST(@BundleNo AS NVARCHAR(20)) ELSE @BundleLetter + N'-' + CAST(@BundleNo AS NVARCHAR(20)) END;
    SET @T += N'{B}{2COL}' + dbo.SIS_fn_TokenEscape(ISNULL(@Serial, N'-')) + N' (' + @BundleNoText + N')|' + dbo.SIS_fn_TokenEscape(ISNULL(@SizeName, N'')) + @NL;
    SET @T += dbo.SIS_fn_TokenEscape(@ProjectName) + @NL;
    SET @T += dbo.SIS_fn_TokenEscape(LTRIM(RTRIM(@ArticleName))) + @NL;

    DECLARE @StyleColor NVARCHAR(220) = LTRIM(RTRIM(ISNULL(@Style, N'') + N' ' + ISNULL(@Color, N'')));
    IF @StyleColor <> N''
        SET @T += dbo.SIS_fn_TokenEscape(@StyleColor) + @NL;
    SET @T += N'{HR}' + @NL;

    -- Line + penjahit (bold).
    DECLARE @LineTailor NVARCHAR(400) = CASE WHEN @LineResourceName IS NULL OR LTRIM(RTRIM(@LineResourceName)) = N''
        THEN ISNULL(@TailorName, N'-') ELSE @LineResourceName + N' - ' + ISNULL(@TailorName, N'-') END;
    SET @T += N'{B}' + dbo.SIS_fn_TokenEscape(@LineTailor) + @NL;

    SET @T += N'{B}Qty OK : ' + CAST(@QtyOk AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectPrint > 0 SET @T += N'Reject Print : ' + CAST(@QtyRejectPrint AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectFabric > 0 SET @T += N'Reject Bahan : ' + CAST(@QtyRejectFabric AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectSewing > 0 SET @T += N'Reject Jahit : ' + CAST(@QtyRejectSewing AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectRework > 0 SET @T += N'Rework : ' + CAST(@QtyRejectRework AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyLost > 0 SET @T += N'Hilang : ' + CAST(@QtyLost AS NVARCHAR(10)) + N' pcs' + @NL;

    -- Note bundle_remarks: satu baris logis, word-wrap otomatis ditangani renderer (tidak
    -- perlu dipecah manual di SP seperti EscPosBuilder.WrapLines lama).
    IF @BundleRemarks IS NOT NULL AND LTRIM(RTRIM(@BundleRemarks)) <> N''
        SET @T += N'Note : ' + dbo.SIS_fn_TokenEscape(@BundleRemarks) + @NL;

    SET @T += N'{HR}' + @NL;

    DECLARE @FooterAt DATETIME2 = ISNULL(@UpdatedAt, @CreatedAt);
    SET @T += FORMAT(@FooterAt, 'dd/MM/yyyy HH:mm');

    -- Tidak menulis {CUT} -- worker otomatis menambahkan {FEED:4}{CUT} di akhir dokumen
    -- (lihat aturan renderer di prompt), sama seperti SP render lain.
    SELECT @T AS TokenText;
END;
GO
