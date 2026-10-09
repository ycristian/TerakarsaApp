-- Prompt 58: daftar pegawai satu line untuk sub-tab "Pegawai" di perangkat stasiun
-- (SELECT saja). Mutasi ada di procedure terpisah: sp_StationEmployee_Manage.sql.
--
-- Berbeda dengan SIS_Employee_GetAll (list admin, semua divisi): di sini SELALU terikat
-- @ResourceId (line operator sesi) dan dipisah per status lewat @IsActive, karena UI-nya
-- toggle "Aktif (n) / Nonaktif (n)".

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_StationEmployee_List
    @ResourceId INT,
    @IsActive   BIT = 1,
    @Search     VARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

    -- Pencarian no. telp mengikuti cara penyimpanannya (hanya digit): kata kunci ikut
    -- dipangkas jadi digit, jadi "0812-2345" tetap ketemu.
    DECLARE @SearchDigits VARCHAR(150) = ISNULL(@Search, '');
    WHILE PATINDEX('%[^0-9]%', @SearchDigits) > 0
        SET @SearchDigits = STUFF(@SearchDigits, PATINDEX('%[^0-9]%', @SearchDigits), 1, '');
    SET @SearchDigits = NULLIF(@SearchDigits, '');

    -- Result 1: daftar pegawai sesuai status yang dipilih.
    SELECT e.employee_id     AS Id,
           e.employee_code   AS EmployeeCode,
           e.employee_name   AS EmployeeName,
           e.position_id     AS PositionId,
           p.position_name   AS PositionName,
           e.phone_no        AS PhoneNo,
           e.is_active       AS IsActive,
           e.join_date       AS JoinDate,
           e.inactive_date   AS InactiveDate,
           e.inactive_reason AS InactiveReason
    FROM employees e
    INNER JOIN positions p ON p.position_id = e.position_id
    WHERE e.deleted_at IS NULL
      AND e.resource_id = @ResourceId
      AND e.is_active = @IsActive
      AND (@Search IS NULL
           OR e.employee_name LIKE '%' + @Search + '%'
           OR (@SearchDigits IS NOT NULL AND e.phone_no LIKE '%' + @SearchDigits + '%'))
    ORDER BY e.employee_name ASC;

    -- Result 2: angka pada toggle Aktif/Nonaktif -- SENGAJA tidak ikut @Search supaya
    -- angkanya tetap jumlah sebenarnya saat PIC sedang mencari.
    SELECT ISNULL(SUM(CASE WHEN e.is_active = 1 THEN 1 ELSE 0 END), 0) AS ActiveCount,
           ISNULL(SUM(CASE WHEN e.is_active = 0 THEN 1 ELSE 0 END), 0) AS InactiveCount
    FROM employees e
    WHERE e.deleted_at IS NULL AND e.resource_id = @ResourceId;
END;
GO
