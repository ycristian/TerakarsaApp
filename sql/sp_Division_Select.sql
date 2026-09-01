-- Pengambilan data divisions (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Division_Manage.sql (SIS_Division_Manage).
--
-- Fix: @SearchTerm kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Division_GetAll
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
        FROM divisions
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@SearchTerm, ' ') tok
                WHERE tok.value <> ''
                  AND NOT (
                        division_code LIKE '%' + tok.value + '%'
                     OR division_name LIKE '%' + tok.value + '%'
                  )
              ));
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'DivisionCode' THEN 'division_code'
            WHEN 'DivisionName' THEN 'division_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'division_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'division_id' THEN '' ELSE ', division_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT division_id AS Id, division_code AS DivisionCode, division_name AS DivisionName,
                   show_in_dashboard AS ShowInDashboard, dashboard_mode AS DashboardMode,
                   dashboard_sort_order AS DashboardSortOrder, default_target_per_person AS DefaultTargetPerPerson,
                   ppic_managed AS PpicManaged,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM divisions
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@SearchTerm, '' '') tok
                    WHERE tok.value <> ''''
                      AND NOT (
                            division_code LIKE ''%'' + tok.value + ''%''
                         OR division_name LIKE ''%'' + tok.value + ''%''
                      )
                  ))
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Division_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT division_id AS Id, division_code AS DivisionCode, division_name AS DivisionName,
           show_in_dashboard AS ShowInDashboard, dashboard_mode AS DashboardMode,
           dashboard_sort_order AS DashboardSortOrder, default_target_per_person AS DefaultTargetPerPerson,
           ppic_managed AS PpicManaged,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM divisions
    WHERE division_id = @Id AND deleted_at IS NULL;
END;
GO

-- Prompt 53: lookup divisi yang boleh dikelola PPIC (dropdown Divisi di module PPIC_EMPLOYEE).
CREATE OR ALTER PROCEDURE SIS_Division_GetPpicManaged
AS
BEGIN
    SET NOCOUNT ON;

    SELECT division_id AS Id, division_code AS DivisionCode, division_name AS DivisionName,
           show_in_dashboard AS ShowInDashboard, dashboard_mode AS DashboardMode,
           dashboard_sort_order AS DashboardSortOrder, default_target_per_person AS DefaultTargetPerPerson,
           ppic_managed AS PpicManaged,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM divisions
    WHERE ppic_managed = 1 AND deleted_at IS NULL
    ORDER BY division_name ASC;
END;
GO
