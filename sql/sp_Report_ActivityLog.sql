-- Prompt 47: Modul Log Aktivitas -- READ-ONLY, listing mentah article_workflow_logs, satu
-- baris tabel = satu baris log hidup, tanpa grouping/agregasi (kecuali TotalQtyOk di COUNT,
-- angka footer). Tidak menyentuh SIS_WorkflowLog_Manage atau SP lain.
--
-- Employee diambil dari bundles.employee_id (penjahit yang ditugaskan ke bundle, Prompt 32).
-- article_workflow_logs.employee_id TIDAK dipakai di sini.
--
-- Semua JOIN ke master yang bisa soft-delete pakai LEFT JOIN dengan filter deleted_at di
-- klausa ON (bukan WHERE) -- baris log lama tidak boleh hilang gara-gara master-nya sudah
-- dihapus (aturan yang sudah berlaku, lihat sp_Report_Bundle.sql).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Report_ActivityLog
    @Action        VARCHAR(10)   = 'LIST',  -- LIST atau COUNT
    @DateFrom      DATETIME2,
    @DateTo        DATETIME2,
    @TimeBasis     VARCHAR(10)   = 'ANY',   -- ANY / CREATED / RECEIVED
    @DivisionId    INT           = NULL,
    @ResourceId    INT           = NULL,
    @EmployeeId    INT           = NULL,
    @ProjectId     INT           = NULL,
    @SearchTerm    VARCHAR(150)  = NULL,
    @PageNumber    INT           = 1,
    @PageSize      INT           = 50,
    @SortColumn    VARCHAR(30)   = NULL,    -- CreatedAt / ReceivedAt / ReceivedByResourceName /
                                             -- EmployeeName (NULL = default waktu terbaru)
    @SortDirection VARCHAR(4)    = 'desc'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'COUNT'
    BEGIN
        SELECT
            COUNT(*) AS TotalCount,
            ISNULL(SUM(awl.qty_ok), 0) AS TotalQtyOk
        FROM article_workflow_logs awl
        LEFT JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id AND aw.deleted_at IS NULL
        LEFT JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
        LEFT JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        WHERE awl.deleted_at IS NULL
          AND (
                (@TimeBasis = 'CREATED' AND awl.created_at BETWEEN @DateFrom AND @DateTo)
             OR (@TimeBasis = 'RECEIVED' AND awl.received_at BETWEEN @DateFrom AND @DateTo)
             OR (@TimeBasis NOT IN ('CREATED', 'RECEIVED') AND (
                    awl.created_at BETWEEN @DateFrom AND @DateTo
                 OR awl.received_at BETWEEN @DateFrom AND @DateTo))
              )
          AND (@DivisionId IS NULL OR awl.division_id = @DivisionId)
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND (@EmployeeId IS NULL OR b.employee_id = @EmployeeId)
          AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
          AND (@SearchTerm IS NULL
               OR b.serial LIKE '%' + @SearchTerm + '%'
               OR p.project_name LIKE '%' + @SearchTerm + '%'
               OR a.article_name LIKE '%' + @SearchTerm + '%'
               OR aw.step_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        SELECT
            awl.workflow_log_id AS WorkflowLogId,
            awl.log_type AS LogType,
            awl.created_at AS CreatedAt,
            awl.received_at AS ReceivedAt,
            awl.updated_at AS UpdatedAt,
            p.project_id AS ProjectId,
            p.project_name AS ProjectName,
            a.article_id AS ArticleId,
            a.article_name AS ArticleName,
            a.style AS Style,
            a.color AS Color,
            aw.step_name AS StepName,
            aw.sort_order AS SortOrder,
            b.bundle_id AS BundleId,
            b.serial AS BundleSerial,
            b.bundle_no AS BundleNo,
            p.bundle_letter AS BundleLetter,
            COALESCE(spdb.size_name, spdn.size_name) AS SizeName,
            awl.division_id AS DivisionId,
            d.division_name AS DivisionName,
            awl.target_division_id AS TargetDivisionId,
            td.division_name AS TargetDivisionName,
            awl.resource_id AS ResourceId,
            r.resource_name AS ResourceName,
            awl.received_by_resource_id AS ReceivedByResourceId,
            rr.resource_name AS ReceivedByResourceName,
            b.employee_id AS EmployeeId,
            emp.employee_name AS EmployeeName,
            awl.qty_ok AS QtyOk,
            awl.qty_reject_print AS QtyRejectPrint,
            awl.qty_reject_fabric AS QtyRejectFabric,
            awl.qty_reject_sewing AS QtyRejectSewing,
            awl.qty_reject_rework AS QtyRejectRework,
            awl.qty_lost AS QtyLost,
            awl.remark AS Remark,
            awl.received_remark AS ReceivedRemark,
            cu.FullName AS CreatedByName,
            CASE WHEN awl.received_at IS NULL THEN 'MENUNGGU' ELSE 'DITERIMA' END AS Status,
            CASE WHEN b.bundle_id IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS CanNavigate,
            ISNULL(aw.print_kupon, CAST(0 AS BIT)) AS PrintKupon
        FROM article_workflow_logs awl
        LEFT JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id AND aw.deleted_at IS NULL
        LEFT JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
        LEFT JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        LEFT JOIN article_sizes aszb ON aszb.article_size_id = b.article_size_id AND aszb.deleted_at IS NULL
        LEFT JOIN size_pack_details spdb ON spdb.size_pack_detail_id = aszb.size_pack_detail_id AND spdb.deleted_at IS NULL
        LEFT JOIN article_sizes aszn ON aszn.article_size_id = awl.article_size_id AND aszn.deleted_at IS NULL
        LEFT JOIN size_pack_details spdn ON spdn.size_pack_detail_id = aszn.size_pack_detail_id AND spdn.deleted_at IS NULL
        LEFT JOIN divisions d ON d.division_id = awl.division_id AND d.deleted_at IS NULL
        LEFT JOIN divisions td ON td.division_id = awl.target_division_id AND td.deleted_at IS NULL
        LEFT JOIN resources r ON r.resource_id = awl.resource_id AND r.deleted_at IS NULL
        LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id AND rr.deleted_at IS NULL
        LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
        LEFT JOIN Users cu ON cu.Id = awl.created_by
        WHERE awl.deleted_at IS NULL
          AND (
                (@TimeBasis = 'CREATED' AND awl.created_at BETWEEN @DateFrom AND @DateTo)
             OR (@TimeBasis = 'RECEIVED' AND awl.received_at BETWEEN @DateFrom AND @DateTo)
             OR (@TimeBasis NOT IN ('CREATED', 'RECEIVED') AND (
                    awl.created_at BETWEEN @DateFrom AND @DateTo
                 OR awl.received_at BETWEEN @DateFrom AND @DateTo))
              )
          AND (@DivisionId IS NULL OR awl.division_id = @DivisionId)
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND (@EmployeeId IS NULL OR b.employee_id = @EmployeeId)
          AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
          AND (@SearchTerm IS NULL
               OR b.serial LIKE '%' + @SearchTerm + '%'
               OR p.project_name LIKE '%' + @SearchTerm + '%'
               OR a.article_name LIKE '%' + @SearchTerm + '%'
               OR aw.step_name LIKE '%' + @SearchTerm + '%')
        -- Default (SortColumn NULL): waktu terbaru dulu (created_at DESC). Klik header client
        -- boleh CreatedAt/ReceivedAt/ReceivedByResourceName (Penerima)/EmployeeName (Penjahit)
        -- -- kolom lain di CASE selalu NULL utk kombinasi yang tidak aktif sehingga tidak
        -- mengganggu urutan, tie-break selalu workflow_log_id DESC supaya paging OFFSET/FETCH
        -- stabil. EmployeeName sengaja diurutkan GANDA: dulu pelaksana/Line (r.resource_name),
        -- baru penjahit (emp.employee_name) -- penjahit yang sama bisa muncul di banyak
        -- line, jadi dikelompokkan per line dulu supaya lebih kebaca.
        ORDER BY
            CASE WHEN @SortColumn = 'ReceivedByResourceName' AND @SortDirection = 'asc' THEN rr.resource_name END ASC,
            CASE WHEN @SortColumn = 'ReceivedByResourceName' AND @SortDirection = 'desc' THEN rr.resource_name END DESC,
            CASE WHEN @SortColumn = 'EmployeeName' AND @SortDirection = 'asc' THEN r.resource_name END ASC,
            CASE WHEN @SortColumn = 'EmployeeName' AND @SortDirection = 'desc' THEN r.resource_name END DESC,
            CASE WHEN @SortColumn = 'EmployeeName' AND @SortDirection = 'asc' THEN emp.employee_name END ASC,
            CASE WHEN @SortColumn = 'EmployeeName' AND @SortDirection = 'desc' THEN emp.employee_name END DESC,
            CASE WHEN @SortColumn = 'ReceivedAt' AND @SortDirection = 'asc' THEN awl.received_at END ASC,
            CASE WHEN @SortColumn = 'ReceivedAt' AND @SortDirection = 'desc' THEN awl.received_at END DESC,
            CASE WHEN @SortColumn = 'CreatedAt' AND @SortDirection = 'asc' THEN awl.created_at END ASC,
            CASE WHEN (@SortColumn IS NULL OR @SortColumn = 'CreatedAt') AND @SortDirection = 'desc' THEN awl.created_at END DESC,
            awl.workflow_log_id DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;
    END
END;
GO
