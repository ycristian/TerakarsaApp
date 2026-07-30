-- Mutasi data employees (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Employee_Select.sql (SIS_Employee_GetAll / SIS_Employee_GetById).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: employees punya filtered unique index (UX_employees_code),
-- dan setting ini "dibekukan" pada saat CREATE PROCEDURE, bukan dibaca dari sesi pemanggil.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Employee_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @EmployeeCode VARCHAR(30) = NULL,
    @EmployeeName VARCHAR(150) = NULL,
    @DivisionId   INT = NULL,
    @PositionId   INT = NULL,
    @ResourceId   INT = NULL,
    @JoinDate     DATE = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Prompt 35: employee_code boleh kosong (penjahit yang belum punya kode tapi sudah mulai
    -- kerja bisa didaftar dulu) -- string kosong/whitespace dinormalisasi jadi NULL supaya
    -- konsisten dengan index unik filtered (UX_employees_code, WHERE employee_code IS NOT NULL).
    SET @EmployeeCode = NULLIF(LTRIM(RTRIM(@EmployeeCode)), '');

    IF @Action = 'CREATE'
    BEGIN
        IF @EmployeeCode IS NOT NULL AND EXISTS (SELECT 1 FROM employees WHERE employee_code = @EmployeeCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode karyawan "%s" sudah digunakan.', 16, 1, @EmployeeCode);
            RETURN;
        END

        INSERT INTO employees (division_id, resource_id, position_id, employee_code, employee_name, join_date, created_at, created_by)
        VALUES (@DivisionId, @ResourceId, @PositionId, @EmployeeCode, @EmployeeName, @JoinDate, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM employees
            WHERE employee_code = @EmployeeCode AND deleted_at IS NULL AND employee_id <> @Id
        )
        BEGIN
            RAISERROR('Kode karyawan "%s" sudah digunakan.', 16, 1, @EmployeeCode);
            RETURN;
        END

        UPDATE employees
        SET division_id = @DivisionId,
            resource_id = @ResourceId,
            position_id = @PositionId,
            employee_code = @EmployeeCode,
            employee_name = @EmployeeName,
            join_date = @JoinDate,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE employees
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END
END;
GO
