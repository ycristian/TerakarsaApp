-- Ad-hoc: hasil kerja (qty_ok) resource Jahit "A1 Heru" per No PO + Nama Artikel,
-- pivot Tanggal ke kanan, periode sama dengan adhoc_hanca_a1heru_pivot_artikel.sql
-- (22/08 - 28/08). "Hasil" = qty_ok pada article_workflow_logs (qty selesai/OK yang
-- dicatat pada baris log step, BUKAN qty_ok yang sudah/belum diterima step berikutnya) --
-- reject/lost tidak dihitung di sini.
-- Tanggal pivot = article_workflow_logs.created_at (tanggal step ini dicatat selesai
-- oleh resource, bukan received_at).
-- Sumber: article_workflow_logs JOIN article_workflows JOIN articles JOIN projects
-- (no_po), filter resource_id = "A1 Heru" (otomatis terbatas ke divisi Sewing karena
-- resource melekat ke satu divisi).
-- Bukan stored procedure -- jalankan manual sesuai kebutuhan, atur @StartDate /
-- @EndDate di bawah.

SET NOCOUNT ON;

DECLARE @StartDate date = '2026-08-22';
DECLARE @EndDate   date = '2026-08-28';
-- Rentang tanggal dicatat, inklusif kedua ujung (22/08 s/d 28/08).

DECLARE @ResourceId int = (
    SELECT TOP 1 resource_id FROM resources
    WHERE deleted_at IS NULL
      AND resource_name LIKE N'%A1%' AND resource_name LIKE N'%Heru%'
);
-- Resource jahit "A1 Heru" dicari via LIKE (case-insensitive default collation), tanpa
-- hardcode ID. Override manual kalau nama resource beda / mau resource lain, contoh:
-- SET @ResourceId = 12;

DECLARE @cols nvarchar(max);
DECLARE @sql  nvarchar(max);

;WITH dates AS (
    SELECT @StartDate AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d)
    FROM dates
    WHERE d < @EndDate
)
SELECT @cols = STRING_AGG(
    N'SUM(CASE WHEN log_date = ''' + CONVERT(varchar(10), d, 120) + N''' THEN qty_ok ELSE 0 END) AS ' + QUOTENAME(CONVERT(varchar(10), d, 120)),
    N',' + CHAR(13) + CHAR(10)
) WITHIN GROUP (ORDER BY d)
FROM dates
OPTION (MAXRECURSION 1000);

SET @sql = N'
;WITH src AS (
    SELECT
        COALESCE(p.no_po, N''-'') AS no_po,
        a.article_name AS article_name,
        CONVERT(date, l.created_at) AS log_date,
        l.qty_ok AS qty_ok
    FROM article_workflow_logs l
    JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id
    JOIN articles a           ON a.article_id = aw.article_id
    JOIN projects p           ON p.project_id = a.project_id
    WHERE l.deleted_at IS NULL
      AND CONVERT(date, l.created_at) >= @p_start
      AND CONVERT(date, l.created_at) <= @p_end
      AND l.resource_id = @p_resource_id
),
pvt AS (
    SELECT
        no_po AS [No PO],
        article_name AS [Nama Artikel],
        ' + @cols + N',
        SUM(qty_ok) AS [Total]
    FROM src
    GROUP BY no_po, article_name

    UNION ALL

    SELECT
        N''TOTAL'' AS [No PO],
        N'''' AS [Nama Artikel],
        ' + @cols + N',
        SUM(qty_ok) AS [Total]
    FROM src
)
SELECT *
FROM pvt
ORDER BY CASE WHEN [No PO] = N''TOTAL'' THEN 1 ELSE 0 END, [No PO], [Nama Artikel];';

EXEC sp_executesql @sql,
    N'@p_start date, @p_end date, @p_resource_id int',
    @p_start = @StartDate, @p_end = @EndDate, @p_resource_id = @ResourceId;
