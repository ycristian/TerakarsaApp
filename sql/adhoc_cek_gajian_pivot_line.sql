-- Ad-hoc: cek data gajian -- qty done (qty_ok) per Nama Line + Employee, pivot Tanggal
-- ke kanan. Employee diambil dari (urutan fallback): employee di log workflow ->
-- employee di bundle (bundles.employee_id) -> remark bundle (bundles.remarks, setara
-- employee name bundle) -> '-'.
-- Kolom [Total] = total qty di seluruh rentang tanggal; baris TOTAL di bawah = total
-- qty semua Line+Employee per tanggal.
-- Sumber: article_workflow_logs -- resource_id = Line, employee_id = pelaksana.
-- Baris non-bundle (bundle_id NULL, mis. Cutting) tidak punya data bundle -- who = '-'
-- kalau employee log juga kosong.
-- Bukan stored procedure -- jalankan manual sesuai kebutuhan, atur @StartDateTime /
-- @EndDateTime di bawah.

SET NOCOUNT ON;

DECLARE @EndDateTime   datetime2 = DATEADD(HOUR, 10, CONVERT(datetime2, CONVERT(date, GETDATE())));
DECLARE @StartDateTime datetime2 = DATEADD(DAY, -7, @EndDateTime);
-- Default di atas = Sabtu minggu lalu jam 10:00 s/d hari ini jam 10:00.
-- Override manual kalau perlu, contoh:
-- SET @StartDateTime = '2026-08-01T10:00:00';
-- SET @EndDateTime   = '2026-08-08T10:00:00';

DECLARE @DivisionId int = (
    SELECT TOP 1 division_id FROM divisions
    WHERE deleted_at IS NULL
      AND (division_code LIKE N'%SEW%' OR division_name LIKE N'%Sew%' OR division_name LIKE N'%Jahit%')
);
-- Default di atas = divisi Sewing (dicari dari division_code/division_name).
-- NULL = semua divisi. Override manual kalau nama divisinya beda / mau divisi lain, contoh:
-- SET @DivisionId = 3;

DECLARE @cols nvarchar(max);
DECLARE @sql  nvarchar(max);

;WITH dates AS (
    SELECT CONVERT(date, @StartDateTime) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d)
    FROM dates
    WHERE d < CONVERT(date, DATEADD(SECOND, -1, @EndDateTime))
)
SELECT @cols = STRING_AGG(
    N'SUM(CASE WHEN log_date_str = ''' + CONVERT(varchar(10), d, 120) + N''' THEN qty_ok ELSE 0 END) AS ' + QUOTENAME(CONVERT(varchar(10), d, 120)),
    N',' + CHAR(13) + CHAR(10)
) WITHIN GROUP (ORDER BY d)
FROM dates
OPTION (MAXRECURSION 1000);

SET @sql = N'
;WITH src AS (
    SELECT
        r.resource_name AS line_name,
        COALESCE(e.employee_name, eb.employee_name, b.remarks, N''-'') AS who,
        CONVERT(varchar(10), l.created_at, 120) AS log_date_str,
        l.qty_ok AS qty_ok
    FROM article_workflow_logs l
    JOIN resources r        ON r.resource_id = l.resource_id
    LEFT JOIN employees e   ON e.employee_id = l.employee_id
    LEFT JOIN bundles b     ON b.bundle_id = l.bundle_id
    LEFT JOIN employees eb  ON eb.employee_id = b.employee_id
    WHERE l.created_at >= @p_start
      AND l.created_at <  @p_end
      AND l.deleted_at IS NULL
      AND l.resource_id IS NOT NULL
      AND (@p_division_id IS NULL OR l.division_id = @p_division_id)
),
pvt AS (
    SELECT
        line_name AS [Nama Line],
        who AS [Employee/Remark],
        ' + @cols + N',
        SUM(qty_ok) AS [Total]
    FROM src
    GROUP BY line_name, who

    UNION ALL

    SELECT
        N''TOTAL'' AS [Nama Line],
        N'''' AS [Employee/Remark],
        ' + @cols + N',
        SUM(qty_ok) AS [Total]
    FROM src
)
SELECT *
FROM pvt
ORDER BY CASE WHEN [Nama Line] = N''TOTAL'' THEN 1 ELSE 0 END, [Nama Line], [Employee/Remark];';

EXEC sp_executesql @sql,
    N'@p_start datetime2, @p_end datetime2, @p_division_id int',
    @p_start = @StartDateTime, @p_end = @EndDateTime, @p_division_id = @DivisionId;
