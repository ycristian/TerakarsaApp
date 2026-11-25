/* =====================================================================
   fix -- Nama personel DPMU-001 tersimpan "??????????????????"
          (2026-11-18). Penyebab: isian form memakai huruf Unicode khusus
          (mis. huruf "tebal" 𝐀𝐁𝐂 dari media sosial) yang tidak muat di
          kolom varchar -> SQL Server menggantinya dengan '?'.
          Nama benar dari owner: Sugiyanto.

   - Lewat tni.SIS_Personel_Manage @Action = 'UPDATE'; field lain (NRP,
     pangkat, no HP, gender) diisi ulang dengan nilai yang sekarang.
   - kode_ref TIDAK berubah (sudah tercetak di kartu).
   - Hanya mengubah baris yang namanya masih berisi '?' -> aman dijalankan ulang.
   - @UserId: isi dengan user id (tabel Users) yang melakukan perbaikan;
     NULL = updated_by dibiarkan kosong.
   ===================================================================== */
-- Wajib ON: tni.personel punya filtered index (sqlcmd default-nya OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @UserId INT = NULL;   -- <-- isi user id pelaku perbaikan

DECLARE @Id INT, @Nrp VARCHAR(30), @Pangkat VARCHAR(50), @NoHp VARCHAR(30),
        @Gender VARCHAR(20), @NamaLama VARCHAR(150);

SELECT @Id = p.personel_id, @Nrp = p.nrp, @Pangkat = p.pangkat, @NoHp = p.no_hp,
       @Gender = p.gender, @NamaLama = p.nama
FROM tni.personel p
JOIN tni.orders o ON o.order_id = p.order_id AND o.is_active = 1
WHERE p.kode_ref = 'DPMU-001'
  AND p.deleted_at IS NULL;

IF @Id IS NULL
    PRINT 'DPMU-001 tidak ditemukan di order aktif -- tidak ada perubahan.';
ELSE IF CHARINDEX('?', @NamaLama) = 0
    PRINT CONCAT('DPMU-001 sudah bernama "', @NamaLama, '" -- tidak ada perubahan.');
ELSE
BEGIN
    EXEC tni.SIS_Personel_Manage
        @Action  = 'UPDATE',
        @Id      = @Id,
        @Nrp     = @Nrp,
        @Nama    = 'Sugiyanto',
        @Pangkat = @Pangkat,
        @NoHp    = @NoHp,
        @Gender  = @Gender,
        @UserId  = @UserId;

    PRINT CONCAT('DPMU-001 (personel_id ', @Id, '): "', @NamaLama, '" -> "Sugiyanto"');
END

SELECT personel_id, kode_ref, pangkat, nama, nrp
FROM tni.personel
WHERE kode_ref = 'DPMU-001' AND deleted_at IS NULL;
GO
