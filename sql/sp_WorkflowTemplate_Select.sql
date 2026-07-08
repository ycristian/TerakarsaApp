-- Pengambilan data workflow_templates (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_WorkflowTemplate_Manage.sql (SIS_WorkflowTemplate_Manage).
-- GetById hanya mengembalikan header (EF SqlQueryRaw hanya baca 1 result set);
-- steps diambil terpisah lewat SIS_WorkflowTemplateStep_GetByTemplate.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowTemplate_GetAll
    @Action        VARCHAR(10) = 'LIST',  -- LIST atau COUNT
    @SearchTerm    VARCHAR(150) = NULL,
    @PageNumber    INT = 1,
    @PageSize      INT = 10,
    @SortColumn    VARCHAR(50) = NULL,
    @SortDirection VARCHAR(4) = 'asc'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'COUNT'
    BEGIN
        SELECT COUNT(*) AS TotalCount
        FROM workflow_templates wt
        WHERE wt.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR wt.workflow_code LIKE '%' + @SearchTerm + '%'
               OR wt.workflow_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'WorkflowCode' THEN 'wt.workflow_code'
            WHEN 'WorkflowName' THEN 'wt.workflow_name'
            WHEN 'CreatedAt' THEN 'wt.created_at'
            ELSE 'wt.workflow_template_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'wt.workflow_template_id' THEN '' ELSE ', wt.workflow_template_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT wt.workflow_template_id AS Id, wt.workflow_code AS WorkflowCode, wt.workflow_name AS WorkflowName,
                   (SELECT COUNT(*) FROM workflow_template_steps s WHERE s.workflow_template_id = wt.workflow_template_id AND s.deleted_at IS NULL) AS StepCount,
                   wt.created_at AS CreatedAt, wt.created_by AS CreatedBy,
                   wt.updated_at AS UpdatedAt, wt.updated_by AS UpdatedBy
            FROM workflow_templates wt
            WHERE wt.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR wt.workflow_code LIKE ''%'' + @SearchTerm + ''%''
                   OR wt.workflow_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowTemplate_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT wt.workflow_template_id AS Id, wt.workflow_code AS WorkflowCode, wt.workflow_name AS WorkflowName,
           (SELECT COUNT(*) FROM workflow_template_steps s WHERE s.workflow_template_id = wt.workflow_template_id AND s.deleted_at IS NULL) AS StepCount,
           wt.created_at AS CreatedAt, wt.created_by AS CreatedBy,
           wt.updated_at AS UpdatedAt, wt.updated_by AS UpdatedBy
    FROM workflow_templates wt
    WHERE wt.workflow_template_id = @Id AND wt.deleted_at IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowTemplateStep_GetByTemplate
    @WorkflowTemplateId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.step_id AS Id, s.workflow_template_id AS WorkflowTemplateId,
           s.step_name AS StepName, s.division_id AS DivisionId, d.division_name AS DivisionName,
           s.sort_order AS SortOrder, s.requires_bundle AS RequiresBundle
    FROM workflow_template_steps s
    INNER JOIN divisions d ON d.division_id = s.division_id
    WHERE s.workflow_template_id = @WorkflowTemplateId AND s.deleted_at IS NULL
    ORDER BY s.sort_order ASC, s.step_id ASC;
END;
GO
