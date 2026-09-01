-- Ad-hoc: total hanca (bundle) yang DIBUAT (bundles.created_at) per No PO + Nama Artikel,
-- pivot Tanggal ke kanan, filter resource Jahit "A1 Heru" (bundles.resource_id).
-- Metrik = COUNT(bundle_id) per hari -- "hanca" dihitung per bundle, bukan qty pcs.
-- Kolom [Total] = total hanca di seluruh rentang tanggal; baris TOTAL di bawah = total
-- hanca semua artikel per tanggal.
-- Sumber: bundles (created_at = tanggal hanca dibuat) JOIN articles (nama artikel)
-- JOIN projects (no_po) JOIN resources (filter nama resource jahit).
-- Bukan stored procedure -- jalankan manual sesuai kebutuhan, atur @StartDate /
-- @EndDate dan @ResourceNameLike di bawah.

SET NOCOUNT ON;

DECLARE @StartDate date = '2026-08-22';
DECLARE @EndDate   date = '2026-08-28';
-- Rentang tanggal dibuat, inklusif kedua ujung (22/08 s/d 28/08).

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
    N'SUM(CASE WHEN bundle_date = ''' + CONVERT(varchar(10), d, 120) + N''' THEN 1 ELSE 0 END) AS ' + QUOTENAME(CONVERT(varchar(10), d, 120)),
    N',' + CHAR(13) + CHAR(10)
) WITHIN GROUP (ORDER BY d)
FROM dates
OPTION (MAXRECURSION 1000);

SET @sql = N'
;WITH src AS (
    SELECT
        COALESCE(p.no_po, N''-'') AS no_po,
        a.article_name AS article_name,
        CONVERT(date, b.created_at) AS bundle_date
    FROM bundles b
    JOIN articles a ON a.article_id = b.article_id
    JOIN projects p ON p.project_id = a.project_id
    WHERE b.deleted_at IS NULL
      AND CONVERT(date, b.created_at) >= @p_start
      AND CONVERT(date, b.created_at) <= @p_end
      AND b.resource_id = @p_resource_id
),
pvt AS (
    SELECT
        no_po AS [No PO],
        article_name AS [Nama Artikel],
        ' + @cols + N',
        COUNT(*) AS [Total]
    FROM src
    GROUP BY no_po, article_name

    UNION ALL

    SELECT
        N''TOTAL'' AS [No PO],
        N'''' AS [Nama Artikel],
        ' + @cols + N',
        COUNT(*) AS [Total]
    FROM src
)
SELECT *
FROM pvt
ORDER BY CASE WHEN [No PO] = N''TOTAL'' THEN 1 ELSE 0 END, [No PO], [Nama Artikel];';

EXEC sp_executesql @sql,
    N'@p_start date, @p_end date, @p_resource_id int',
    @p_start = @StartDate, @p_end = @EndDate, @p_resource_id = @ResourceId;
