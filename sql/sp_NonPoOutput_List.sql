-- Prompt 59: isi modal detail "Di luar PO - {periode}" di tab Rekap Produksi stasiun.
-- SELECT saja. Mutasi ada di sp_NonPoOutput_Manage.sql (SIS_NonPoOutput_Manage).
--
-- Agregat per TANGGAL untuk baris matriks "Di luar PO" TIDAK di sini -- itu result set 3
-- dari SIS_Station_RekapProduksi, supaya satu kali buka tab cukup satu round-trip.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_NonPoOutput_List
    @ResourceId      INT,
    @PayrollPeriodId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT npo.non_po_output_id AS NonPoOutputId,
           npo.output_at AS OutputAt,
           npo.qty AS Qty,
           npo.unit_price AS UnitPrice,
           -- Nilai upah catatan ini; dihitung di SP supaya layar, modal, dan Excel tidak
           -- punya tiga versi pembulatan sendiri-sendiri.
           CAST(npo.qty * npo.unit_price AS DECIMAL(19,4)) AS Nilai,
           npo.remark AS Remark,
           npo.created_at AS CreatedAt
    FROM non_po_outputs npo
    WHERE npo.deleted_at IS NULL
      AND npo.resource_id = @ResourceId
      AND npo.payroll_period_id = @PayrollPeriodId
    ORDER BY npo.output_at ASC, npo.non_po_output_id ASC;
END;
GO
