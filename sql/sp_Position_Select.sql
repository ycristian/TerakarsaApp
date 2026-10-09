-- Pengambilan data positions (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Position_Manage.sql (SIS_Position_Manage).
--
-- Fix: @SearchTerm kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Position_GetAll
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
        FROM positions
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@SearchTerm, ' ') tok
                WHERE tok.value <> '' AND NOT (position_name LIKE '%' + tok.value + '%')
              ));
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'PositionName' THEN 'position_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'position_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'position_id' THEN '' ELSE ', position_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT p.position_id AS Id, p.position_name AS PositionName,
                   p.is_gate_operator AS IsGateOperator,
                   p.created_at AS CreatedAt, p.created_by AS CreatedBy,
                   p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
                   ISNULL(STUFF((SELECT '', '' + d.division_name
                               FROM division_positions dp
                               INNER JOIN divisions d ON d.division_id = dp.division_id AND d.deleted_at IS NULL
                               WHERE dp.position_id = p.position_id AND dp.deleted_at IS NULL
                               ORDER BY d.division_name
                               FOR XML PATH('''')), 1, 2, ''''), '''') AS DivisionNames
            FROM positions p
            WHERE p.deleted_at IS NULL
              AND (@SearchTerm IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@SearchTerm, '' '') tok
                    WHERE tok.value <> '''' AND NOT (position_name LIKE ''%'' + tok.value + ''%'')
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

CREATE OR ALTER PROCEDURE SIS_Position_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.position_id AS Id, p.position_name AS PositionName,
           p.is_gate_operator AS IsGateOperator,
           p.created_at AS CreatedAt, p.created_by AS CreatedBy,
           p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
           ISNULL(STUFF((SELECT ', ' + d.division_name
                         FROM division_positions dp
                         INNER JOIN divisions d ON d.division_id = dp.division_id AND d.deleted_at IS NULL
                         WHERE dp.position_id = p.position_id AND dp.deleted_at IS NULL
                         ORDER BY d.division_name
                         FOR XML PATH('')), 1, 2, ''), '') AS DivisionNames
    FROM positions p
    WHERE p.position_id = @Id AND p.deleted_at IS NULL;
END;
GO

-- Prompt 58 (lanjutan): divisi yang dipilih untuk satu jabatan -- dipakai form Master Jabatan
-- untuk mencentang ulang pilihan yang sudah tersimpan.
CREATE OR ALTER PROCEDURE SIS_Position_GetDivisions
    @PositionId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Satu kolom saja: pemanggilnya hanya butuh id untuk mencentang ulang checkbox.
    SELECT d.division_id AS DivisionId
    FROM division_positions dp
    INNER JOIN divisions d ON d.division_id = dp.division_id AND d.deleted_at IS NULL
    WHERE dp.position_id = @PositionId AND dp.deleted_at IS NULL
    ORDER BY d.division_name ASC;
END;
GO

-- Prompt 58 (lanjutan): pilihan "Jabatan" untuk satu divisi -- dipakai form pegawai di
-- stasiun (divisi diambil dari token perangkat).
--
-- FALLBACK yang disengaja: kalau divisi ini BELUM punya satu pun jabatan terpetakan, semua
-- jabatan dikembalikan. Dengan begitu fitur ini tidak memblokir pendaftaran pegawai di divisi
-- yang pemetaannya belum diisi admin (lihat alter_58b_division_positions.sql).
CREATE OR ALTER PROCEDURE SIS_Position_GetByDivision
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM division_positions dp
        INNER JOIN positions p ON p.position_id = dp.position_id AND p.deleted_at IS NULL
        WHERE dp.division_id = @DivisionId AND dp.deleted_at IS NULL
    )
    BEGIN
        SELECT p.position_id AS Id, p.position_name AS PositionName,
               p.is_gate_operator AS IsGateOperator,
               p.created_at AS CreatedAt, p.created_by AS CreatedBy,
               p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
               CAST('' AS VARCHAR(MAX)) AS DivisionNames
        FROM division_positions dp
        INNER JOIN positions p ON p.position_id = dp.position_id AND p.deleted_at IS NULL
        WHERE dp.division_id = @DivisionId AND dp.deleted_at IS NULL
        ORDER BY p.position_name ASC;
        RETURN;
    END

    SELECT p.position_id AS Id, p.position_name AS PositionName,
           p.is_gate_operator AS IsGateOperator,
           p.created_at AS CreatedAt, p.created_by AS CreatedBy,
           p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
           CAST('' AS VARCHAR(MAX)) AS DivisionNames
    FROM positions p
    WHERE p.deleted_at IS NULL
    ORDER BY p.position_name ASC;
END;
GO
