-- Prompt 53: mutasi karyawan lewat module PPIC_EMPLOYEE (CREATE/UPDATE/DELETE/SETACTIVE).
-- Pintu masuk MANDIRI, terpisah dari SIS_Employee_Manage (dipakai MASTER_EMPLOYEE) -- guard
-- cakupan PPIC (ppic_managed) ditegakkan DI SINI, bukan hanya di controller, supaya
-- division_id dari client tidak bisa dipakai menembus batasan. Pengambilan data ada di
-- procedure terpisah: sp_PpicEmployee_Select.sql.
--
-- DELETE: soft delete hanya kalau karyawan belum pernah dipakai di transaksi apa pun.
-- Penelusuran FK ke employees(employee_id) lewat sys.foreign_keys (per Prompt 53, 2026-08-11)
-- menemukan 6 kolom di 4 tabel -- semuanya dicek eksplisit di bawah:
--   article_workflow_logs.employee_id, bundles.employee_id,
--   projects.project_md, projects.project_pic,
--   material_movement.giver_employee_id, material_movement.received_employee_id
-- Baris referensi yang sudah soft-delete TIDAK dihitung "dipakai" (pola sama seperti guard
-- delete lain di sistem, mis. SIS_WorkflowLog_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_PpicEmployee_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @EmployeeCode VARCHAR(30) = NULL,
    @EmployeeName VARCHAR(150) = NULL,
    @DivisionId   INT = NULL,
    @PositionId   INT = NULL,
    @ResourceId   INT = NULL,
    @JoinDate     DATE = NULL,
    @IsActive     BIT = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @EmployeeCode = NULLIF(LTRIM(RTRIM(@EmployeeCode)), '');

    -- CREATE/UPDATE: divisi TUJUAN wajib dikelola PPIC.
    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM divisions WHERE division_id = @DivisionId AND ppic_managed = 1 AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Divisi ini tidak dikelola PPIC.', 16, 1);
            RETURN;
        END
    END

    -- UPDATE/DELETE/SETACTIVE: divisi karyawan yang TERSIMPAN SEKARANG juga wajib dikelola PPIC
    -- (mencegah PPIC menyentuh karyawan divisi lain lewat @Id yang bukan miliknya).
    IF @Action IN ('UPDATE', 'DELETE', 'SETACTIVE')
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM employees e
            INNER JOIN divisions d ON d.division_id = e.division_id
            WHERE e.employee_id = @Id AND e.deleted_at IS NULL AND d.ppic_managed = 1 AND d.deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Karyawan ini di luar wewenang PPIC.', 16, 1);
            RETURN;
        END
    END

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
        DECLARE @DelEmployeeName VARCHAR(150);
        SELECT @DelEmployeeName = employee_name FROM employees WHERE employee_id = @Id;

        IF EXISTS (SELECT 1 FROM article_workflow_logs WHERE employee_id = @Id AND deleted_at IS NULL)
           OR EXISTS (SELECT 1 FROM bundles WHERE employee_id = @Id AND deleted_at IS NULL)
           OR EXISTS (SELECT 1 FROM projects WHERE (project_md = @Id OR project_pic = @Id) AND deleted_at IS NULL)
           OR EXISTS (SELECT 1 FROM material_movement WHERE (giver_employee_id = @Id OR received_employee_id = @Id) AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Karyawan "%s" sudah dipakai di transaksi dan tidak bisa dihapus. Nonaktifkan saja.', 16, 1, @DelEmployeeName);
            RETURN;
        END

        UPDATE employees
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'SETACTIVE'
    BEGIN
        UPDATE employees
        SET is_active = @IsActive,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END
END;
GO
