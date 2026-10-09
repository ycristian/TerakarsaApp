-- Prompt 70 -- Pengambilan data employee_cards (SELECT saja, tidak menyentuh data).
-- Mutasi ada di sp_EmployeeCard_Manage.sql (SIS_EmployeeCard_Manage).
--
-- @SearchTerm memakai pola pencarian antar-atribut yang sama dengan master lain: tiap kata
-- dipisah spasi dicek independen ke SEMUA kolom (STRING_SPLIT) -- lihat sp_Employee_Select.sql.
-- Tidak ada paging: 150-an kartu, halaman admin memuat semuanya sekali lalu memfilter di sisi
-- UI (sama seperti daftar master kecil lain).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_EmployeeCard_List
    @Search      VARCHAR(150) = NULL,
    @OnlyActive  BIT = 0            -- 1 = hanya card_status 'AKTIF'
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search, ''))), '');

    SELECT ec.employee_card_id      AS Id,
           ec.card_uid              AS CardUid,
           ec.employee_id           AS EmployeeId,
           e.employee_name          AS EmployeeName,
           e.employee_code          AS EmployeeCode,
           e.division_id            AS DivisionId,
           d.division_name          AS DivisionName,
           p.position_name          AS PositionName,
           e.resource_id            AS ResourceId,
           r.resource_name          AS ResourceName,
           r.color_hex              AS ColorHex,
           ec.card_type             AS CardType,
           ec.card_status           AS CardStatus,
           ec.issued_at             AS IssuedAt,
           ec.issued_by_employee_id AS IssuedByEmployeeId,
           ib.employee_name         AS IssuedByEmployeeName,
           ec.remarks               AS Remarks
    FROM employee_cards ec
    INNER JOIN employees e ON e.employee_id = ec.employee_id
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    -- LEFT JOIN + filter deleted_at DI KLAUSA ON supaya baris kartu tidak ikut hilang kalau
    -- resource/satpam penerbitnya sudah dihapus.
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    LEFT JOIN employees ib ON ib.employee_id = ec.issued_by_employee_id AND ib.deleted_at IS NULL
    WHERE ec.deleted_at IS NULL
      AND (@OnlyActive = 0 OR ec.card_status = 'AKTIF')
      AND (@Search IS NULL OR NOT EXISTS (
            SELECT 1 FROM STRING_SPLIT(@Search, ' ') tok
            WHERE tok.value <> ''
              AND NOT (
                    ec.card_uid LIKE '%' + tok.value + '%'
                 OR e.employee_name LIKE '%' + tok.value + '%'
                 OR ISNULL(e.employee_code, '') LIKE '%' + tok.value + '%'
                 OR d.division_name LIKE '%' + tok.value + '%'
                 OR p.position_name LIKE '%' + tok.value + '%'
                 OR ISNULL(r.resource_name, '') LIKE '%' + tok.value + '%'
              )
          ))
    -- Kartu aktif di atas, lalu yang terbaru -- supaya kartu pengganti muncul di atas kartu
    -- lama orang yang sama.
    ORDER BY CASE WHEN ec.card_status = 'AKTIF' THEN 0 ELSE 1 END ASC,
             ec.issued_at DESC,
             ec.employee_card_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_EmployeeCard_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ec.employee_card_id      AS Id,
           ec.card_uid              AS CardUid,
           ec.employee_id           AS EmployeeId,
           e.employee_name          AS EmployeeName,
           e.employee_code          AS EmployeeCode,
           e.division_id            AS DivisionId,
           d.division_name          AS DivisionName,
           p.position_name          AS PositionName,
           e.resource_id            AS ResourceId,
           r.resource_name          AS ResourceName,
           r.color_hex              AS ColorHex,
           ec.card_type             AS CardType,
           ec.card_status           AS CardStatus,
           ec.issued_at             AS IssuedAt,
           ec.issued_by_employee_id AS IssuedByEmployeeId,
           ib.employee_name         AS IssuedByEmployeeName,
           ec.remarks               AS Remarks
    FROM employee_cards ec
    INNER JOIN employees e ON e.employee_id = ec.employee_id
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    LEFT JOIN employees ib ON ib.employee_id = ec.issued_by_employee_id AND ib.deleted_at IS NULL
    WHERE ec.employee_card_id = @Id AND ec.deleted_at IS NULL;
END;
GO
