-- Pengambilan data employees (SELECT saja, tidak menyentuh data).
-- INNER JOIN divisions & positions (wajib diisi), LEFT JOIN resources (resource_id nullable).
-- Mutasi (create/update/delete) ada di sp_Employee_Manage.sql (SIS_Employee_Manage).
--
-- Fix: @SearchTerm kini pencarian antar-atribut -- tiap kata (dipisah spasi) dicek independen
--   ke SEMUA kolom via STRING_SPLIT, baris cocok kalau SEMUA kata ketemu di SUATU kolom (boleh
--   kolom berbeda per kata). Pola yang sama diterapkan ke semua SP list search lain di sistem.

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
          -- Fix: pencarian antar-atribut -- tiap kata di @SearchTerm dicek independen ke
          -- SEMUA kolom (boleh kolom berbeda per kata), baris cocok kalau SEMUA kata ketemu.
          AND (@SearchTerm IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@SearchTerm, ' ') s
                WHERE s.value <> ''
                  AND NOT (
                        e.employee_code LIKE '%' + s.value + '%'
                     OR e.employee_name LIKE '%' + s.value + '%'
                     OR d.division_name LIKE '%' + s.value + '%'
                     OR p.position_name LIKE '%' + s.value + '%'
                  )
              ));
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
                   e.join_date AS JoinDate, e.is_active AS IsActive,
                   e.created_at AS CreatedAt, e.created_by AS CreatedBy,
                   e.updated_at AS UpdatedAt, e.updated_by AS UpdatedBy
            FROM employees e
            INNER JOIN divisions d ON d.division_id = e.division_id
            INNER JOIN positions p ON p.position_id = e.position_id
            LEFT JOIN resources r ON r.resource_id = e.resource_id
            WHERE e.deleted_at IS NULL
              AND (@SearchTerm IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@SearchTerm, '' '') s
                    WHERE s.value <> ''''
                      AND NOT (
                            e.employee_code LIKE ''%'' + s.value + ''%''
                         OR e.employee_name LIKE ''%'' + s.value + ''%''
                         OR d.division_name LIKE ''%'' + s.value + ''%''
                         OR p.position_name LIKE ''%'' + s.value + ''%''
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
           e.join_date AS JoinDate, e.is_active AS IsActive,
           e.created_at AS CreatedAt, e.created_by AS CreatedBy,
           e.updated_at AS UpdatedAt, e.updated_by AS UpdatedBy
    FROM employees e
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id
    WHERE e.employee_id = @Id AND e.deleted_at IS NULL;
END;
GO

-- Prompt 53: lookup employee AKTIF untuk dropdown umum (bukan cascading resource/divisi) --
-- dipakai MD/PIC project (Prompt 53 mengganti pemakaian ulang SIS_Employee_GetAll LIST yang
-- lama, karena SP itu juga dipakai list admin Master Karyawan yang WAJIB tetap menampilkan
-- karyawan nonaktif). Karyawan nonaktif yang SUDAH tersimpan sebagai MD/PIC tetap ditangani
-- di sisi client (fallback dari data project yang sudah di-load), bukan di SP ini.
CREATE OR ALTER PROCEDURE SIS_Employee_GetActive
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.employee_id AS Id,
           e.employee_code AS EmployeeCode, e.employee_name AS EmployeeName,
           e.division_id AS DivisionId, d.division_name AS DivisionName,
           e.position_id AS PositionId, p.position_name AS PositionName,
           e.resource_id AS ResourceId, r.resource_name AS ResourceName,
           e.join_date AS JoinDate, e.is_active AS IsActive,
           e.created_at AS CreatedAt, e.created_by AS CreatedBy,
           e.updated_at AS UpdatedAt, e.updated_by AS UpdatedBy
    FROM employees e
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id
    WHERE e.deleted_at IS NULL AND e.is_active = 1
    ORDER BY e.employee_name ASC;
END;
GO

-- Prompt 32: lookup employee hidup untuk dropdown "Penjahit" (cascading di bawah dropdown
-- Line/resource) -- pola meniru SIS_Resource_GetActiveByDivision.
-- Prompt 53: tambah filter is_active = 1 -- karyawan nonaktif hilang dari dropdown ini
-- (nilai yang sudah tersimpan di bundle lama ditangani fallback di client, lihat BundleManager.razor).
CREATE OR ALTER PROCEDURE SIS_Employee_GetActiveByResource
    @ResourceId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT employee_id AS Id, employee_name AS EmployeeName, employee_code AS EmployeeCode
    FROM employees
    WHERE resource_id = @ResourceId
      AND deleted_at IS NULL
      AND is_active = 1
    ORDER BY employee_name ASC;
END;
GO

-- Prompt 47: dropdown "Employee" cascading dari Divisi (bukan Resource) di modul Log
-- Aktivitas -- pola meniru SIS_Employee_GetActiveByResource di atas.
-- Prompt 53: tambah filter is_active = 1 -- lihat komentar di SIS_Employee_GetActiveByResource.
CREATE OR ALTER PROCEDURE SIS_Employee_GetActiveByDivision
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT employee_id AS Id, employee_name AS EmployeeName, employee_code AS EmployeeCode
    FROM employees
    WHERE division_id = @DivisionId
      AND deleted_at IS NULL
      AND is_active = 1
    ORDER BY employee_name ASC;
END;
GO

-- Prompt 53: saran kode karyawan otomatis {division_code}-{4 digit}, nomor urut berjalan
-- PER DIVISI. Hanya memberi saran -- keunikan tetap divalidasi di SIS_Employee_Manage/
-- SIS_PpicEmployee_Manage saat simpan. Nomor tidak pernah dipakai ulang: MAX dihitung dari
-- SEMUA baris employees ber-kode dengan pola divisi ini, termasuk yang nonaktif dan yang
-- sudah soft-delete.
CREATE OR ALTER PROCEDURE SIS_Employee_NextCode
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DivisionCode VARCHAR(30);
    SELECT @DivisionCode = division_code FROM divisions WHERE division_id = @DivisionId AND deleted_at IS NULL;

    IF @DivisionCode IS NULL
    BEGIN
        SELECT CAST(NULL AS VARCHAR(40)) AS SuggestedCode;
        RETURN;
    END

    DECLARE @Prefix VARCHAR(35) = @DivisionCode + '-';
    DECLARE @MaxNumber INT;

    -- Pola dasar minimal 4 digit (spesifikasi), tapi juga menangkap kode 5+ digit yang sudah
    -- lewat 9999 (spesifikasi: jangan dipotong). Baris yang bagian angkanya bukan digit murni
    -- (mis. kode manual "EM-0001X") sengaja dibuang lewat NOT LIKE '%[^0-9]%'.
    SELECT @MaxNumber = MAX(CAST(SUBSTRING(employee_code, LEN(@Prefix) + 1, LEN(employee_code) - LEN(@Prefix)) AS INT))
    FROM employees
    WHERE employee_code LIKE @Prefix + '[0-9][0-9][0-9][0-9]%'
      AND SUBSTRING(employee_code, LEN(@Prefix) + 1, LEN(employee_code) - LEN(@Prefix)) NOT LIKE '%[^0-9]%';

    SELECT @Prefix + RIGHT('0000' + CAST(ISNULL(@MaxNumber, 0) + 1 AS VARCHAR(10)), 4) AS SuggestedCode;
END;
GO
