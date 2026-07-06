-- Mutasi data buyers (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Buyer_Select.sql (SIS_Buyer_GetAll / SIS_Buyer_GetById).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: buyers punya filtered unique index (UX_buyers_code),
-- dan setting ini "dibekukan" pada saat CREATE PROCEDURE, bukan dibaca dari sesi pemanggil.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Buyer_Manage
    @Action     VARCHAR(20),
    @Id         INT = NULL,
    @BuyerCode  VARCHAR(30) = NULL,
    @BuyerName  VARCHAR(150) = NULL,
    @Address    VARCHAR(255) = NULL,
    @Phone      VARCHAR(30) = NULL,
    @UserId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM buyers WHERE buyer_code = @BuyerCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode buyer "%s" sudah digunakan.', 16, 1, @BuyerCode);
            RETURN;
        END

        INSERT INTO buyers (buyer_code, buyer_name, [address], phone, created_at, created_by)
        VALUES (@BuyerCode, @BuyerName, @Address, @Phone, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM buyers
            WHERE buyer_code = @BuyerCode AND deleted_at IS NULL AND buyer_id <> @Id
        )
        BEGIN
            RAISERROR('Kode buyer "%s" sudah digunakan.', 16, 1, @BuyerCode);
            RETURN;
        END

        UPDATE buyers
        SET buyer_code = @BuyerCode,
            buyer_name = @BuyerName,
            [address] = @Address,
            phone = @Phone,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE buyer_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE buyers
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE buyer_id = @Id AND deleted_at IS NULL;
    END
END;
GO
