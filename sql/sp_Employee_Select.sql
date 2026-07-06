-- Pengambilan data employees (SELECT saja, tidak menyentuh data).
-- INNER JOIN divisions & positions (wajib diisi), LEFT JOIN resources (resource_id nullable).
-- Mutasi (create/update/delete) ada di sp_Employee_Manage.sql (SIS_Employee_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Employee_GetAll
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
        FROM employees e
        INNER JOIN divisions d ON d.division_id = e.division_id
        INNER JOIN positions p ON p.position_id = e.position_id
        LEFT JOIN resources r ON r.resource_id = e.resource_id
        WHERE e.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR e.employee_code LIKE '%' + @SearchTerm + '%'
               OR e.employee_name LIKE '%' + @SearchTerm + '%'
               OR d.division_name LIKE '%' + @SearchTerm + '%'
               OR p.position_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'EmployeeCode' THEN 'e.employee_code'
            WHEN 'EmployeeName' THEN 'e.employee_name'
            WHEN 'DivisionName' THEN 'd.division_name'
            WHEN 'PositionName' THEN 'p.position_name'
            WHEN 'JoinDate' THEN 'e.join_date'
            WHEN 'CreatedAt' THEN 'e.created_at'
            ELSE 'e.employee_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'e.employee_id' THEN '' ELSE ', e.employee_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT e.employee_id AS Id,
                   e.employee_code AS EmployeeCode, e.employee_name AS EmployeeName,
                   e.division_id AS DivisionId, d.division_name AS DivisionName,
                   e.position_id AS PositionId, p.position_name AS PositionName,
                   e.resource_id AS ResourceId, r.resource_name AS ResourceName,
                   e.join_date AS JoinDate,
                   e.created_at AS CreatedAt, e.created_by AS CreatedBy,
                   e.updated_at AS UpdatedAt, e.updated_by AS UpdatedBy
            FROM employees e
            INNER JOIN divisions d ON d.division_id = e.division_id
            INNER JOIN positions p ON p.position_id = e.position_id
            LEFT JOIN resources r ON r.resource_id = e.resource_id
            WHERE e.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR e.employee_code LIKE ''%'' + @SearchTerm + ''%''
                   OR e.employee_name LIKE ''%'' + @SearchTerm + ''%''
                   OR d.division_name LIKE ''%'' + @SearchTerm + ''%''
                   OR p.position_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Employee_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.employee_id AS Id,
           e.employee_code AS EmployeeCode, e.employee_name AS EmployeeName,
           e.division_id AS DivisionId, d.division_name AS DivisionName,
           e.position_id AS PositionId, p.position_name AS PositionName,
           e.resource_id AS ResourceId, r.resource_name AS ResourceName,
           e.join_date AS JoinDate,
           e.created_at AS CreatedAt, e.created_by AS CreatedBy,
           e.updated_at AS UpdatedAt, e.updated_by AS UpdatedBy
    FROM employees e
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id
    WHERE e.employee_id = @Id AND e.deleted_at IS NULL;
END;
GO
