-- Query operasional untuk halaman stasiun (/station), semua berbasis @DivisionId
-- (divisi diambil dari token perangkat, lihat SIS_Station_GetByToken). Hanya menyentuh
-- step level artikel (bundle_id NULL) — alur per-bundle menyusul di Prompt 12.
-- Lookup resource aktif per divisi pakai SP yang sudah ada: SIS_Resource_GetActiveByDivision.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Step milik divisi ini yang step sebelumnya (sort_order tepat di bawahnya, hidup)
-- sudah COMPLETED dengan target_division_id = divisi ini, tapi step ini belum RECEIVED.
CREATE OR ALTER PROCEDURE SIS_Station_PendingReceives
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH PrevStep AS (
        SELECT aw.article_workflow_id, aw.article_id, aw.step_name,
               (SELECT TOP 1 aw2.article_workflow_id
                FROM article_workflows aw2
                WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL
                  AND aw2.sort_order < aw.sort_order
                ORDER BY aw2.sort_order DESC) AS PrevArticleWorkflowId
        FROM article_workflows aw
        WHERE aw.division_id = @DivisionId AND aw.deleted_at IS NULL
    )
    SELECT ps.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           ps.step_name AS StepName,
           pcl.qty_ok AS QtyOk, pcl.created_at AS SentAt,
           pd.division_name AS FromDivisionName
    FROM PrevStep ps
    INNER JOIN article_workflows aw ON aw.article_workflow_id = ps.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_workflow_logs pcl
        ON pcl.article_workflow_id = ps.PrevArticleWorkflowId
       AND pcl.[status] = 'COMPLETED' AND pcl.target_division_id = @DivisionId AND pcl.deleted_at IS NULL
    INNER JOIN divisions pd ON pd.division_id = pcl.division_id
    WHERE ps.PrevArticleWorkflowId IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM article_workflow_logs r
          WHERE r.article_workflow_id = ps.article_workflow_id AND r.[status] = 'RECEIVED' AND r.deleted_at IS NULL
      )
    ORDER BY pcl.created_at ASC;
END;
GO

-- Step milik divisi ini yang bisa dikerjakan/diselesaikan: sudah RECEIVED atau
-- merupakan step pertama (sort_order terkecil) artikelnya, belum COMPLETED, dan
-- requires_bundle = 0 (step requires_bundle = 1 belum bisa diselesaikan di sini).
CREATE OR ALTER PROCEDURE SIS_Station_ActiveWork
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT aw.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           CASE WHEN aw.sort_order = (
               SELECT MAX(aw3.sort_order) FROM article_workflows aw3
               WHERE aw3.article_id = aw.article_id AND aw3.deleted_at IS NULL
           ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    WHERE aw.division_id = @DivisionId
      AND aw.deleted_at IS NULL
      AND aw.requires_bundle = 0
      AND NOT EXISTS (
          SELECT 1 FROM article_workflow_logs c
          WHERE c.article_workflow_id = aw.article_workflow_id AND c.[status] = 'COMPLETED' AND c.deleted_at IS NULL
      )
      AND (
          EXISTS (
              SELECT 1 FROM article_workflow_logs r
              WHERE r.article_workflow_id = aw.article_workflow_id AND r.[status] = 'RECEIVED' AND r.deleted_at IS NULL
          )
          OR aw.sort_order = (
              SELECT MIN(aw2.sort_order) FROM article_workflows aw2
              WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL
          )
      )
    ORDER BY p.project_name ASC, a.article_name ASC, aw.sort_order ASC;
END;
GO
