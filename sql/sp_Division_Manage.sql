-- Mutasi data divisions (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Division_Select.sql (SIS_Division_GetAll / SIS_Division_GetById).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: divisions punya filtered unique index (UX_divisions_code),
-- dan setting ini "dibekukan" pada saat CREATE PROCEDURE, bukan dibaca dari sesi pemanggil.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Division_Manage
    @Action                   VARCHAR(20),
    @Id                       INT = NULL,
    @DivisionCode             VARCHAR(30) = NULL,
    @DivisionName             VARCHAR(150) = NULL,
    @ShowInDashboard          BIT = 1,
    @DashboardMode            VARCHAR(20) = 'DIVISION',
    @DashboardSortOrder       INT = 0,
    @DefaultTargetPerPerson   INT = 0,
    -- Prompt 53: @PpicManaged default NULL (bukan 0) -- COALESCE di UPDATE menjaga caller lama
    -- tidak diam-diam mematikan flag "Dikelola PPIC".
    @PpicManaged              BIT = NULL,
    @UserId                   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @DashboardMode NOT IN ('DIVISION', 'RESOURCE')
    BEGIN
        RAISERROR('Mode dashboard hanya boleh DIVISION atau RESOURCE.', 16, 1);
        RETURN;
    END

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM divisions WHERE division_code = @DivisionCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode divisi "%s" sudah digunakan.', 16, 1, @DivisionCode);
            RETURN;
        END

        INSERT INTO divisions (division_code, division_name, show_in_dashboard, dashboard_mode, dashboard_sort_order, default_target_per_person, ppic_managed, created_at, created_by)
        VALUES (@DivisionCode, @DivisionName, @ShowInDashboard, @DashboardMode, @DashboardSortOrder, @DefaultTargetPerPerson, ISNULL(@PpicManaged, 0), SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM divisions
            WHERE division_code = @DivisionCode AND deleted_at IS NULL AND division_id <> @Id
        )
        BEGIN
            RAISERROR('Kode divisi "%s" sudah digunakan.', 16, 1, @DivisionCode);
            RETURN;
        END

        UPDATE divisions
        SET division_code = @DivisionCode,
            division_name = @DivisionName,
            show_in_dashboard = @ShowInDashboard,
            dashboard_mode = @DashboardMode,
            dashboard_sort_order = @DashboardSortOrder,
            default_target_per_person = @DefaultTargetPerPerson,
            ppic_managed = COALESCE(@PpicManaged, ppic_managed),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE division_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE divisions
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE division_id = @Id AND deleted_at IS NULL;
    END
END;
GO
