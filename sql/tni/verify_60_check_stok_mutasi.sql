/* =============================================================
   Verifikasi Prompt 60 bagian 5.3 -- uji CHECK constraint
   tni.stok_mutasi. SELURUH script dibungkus transaksi yang
   di-ROLLBACK: tidak ada baris yang tertinggal di database.
   Aman dijalankan berulang kali.
   ============================================================= */
SET NOCOUNT ON;
SET XACT_ABORT OFF;

BEGIN TRANSACTION;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

-- data sementara (ikut ter-rollback)
INSERT INTO tni.orders (order_code, order_name, tahun, created_by)
VALUES ('UJI_CK_60', 'Uji CHECK Prompt 60', 2026, @U);
DECLARE @O INT = SCOPE_IDENTITY();

INSERT INTO tni.pola_kemeja (kode, target_gender, lingkar_dada_acuan, created_by)
VALUES ('UJI_K', 'P', 100, @U);
DECLARE @PK INT = SCOPE_IDENTITY();

INSERT INTO tni.pola_celana (kode, target_gender, size_angka, created_by)
VALUES ('UJI_C', 'P', 32, @U);
DECLARE @PC INT = SCOPE_IDENTITY();

DECLARE @hasil TABLE (no_uji INT, uji VARCHAR(80), harapan VARCHAR(10), hasil VARCHAR(10), pesan VARCHAR(400));

-- 1. qty = 0 harus DITOLAK
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, jenis_mutasi, qty, created_by)
    VALUES (@O, 'KEMEJA', @PK, 'MASUK', 0, @U);
    INSERT INTO @hasil VALUES (1, 'qty = 0', 'DITOLAK', 'LOLOS', 'BUG: baris berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (1, 'qty = 0', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 2. RUSAK negatif TANPA alasan harus DITOLAK
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, jenis_mutasi, qty, alasan, created_by)
    VALUES (@O, 'KEMEJA', @PK, 'RUSAK', -2, NULL, @U);
    INSERT INTO @hasil VALUES (2, 'RUSAK -2 tanpa alasan', 'DITOLAK', 'LOLOS', 'BUG: baris berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (2, 'RUSAK -2 tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 3. KEDUA kolom pola terisi harus DITOLAK
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, pola_celana_id, jenis_mutasi, qty, created_by)
    VALUES (@O, 'KEMEJA', @PK, @PC, 'MASUK', 5, @U);
    INSERT INTO @hasil VALUES (3, 'pola_kemeja + pola_celana terisi', 'DITOLAK', 'LOLOS', 'BUG: baris berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (3, 'pola_kemeja + pola_celana terisi', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 4. jenis_item CELANA tapi yang terisi pola_kemeja harus DITOLAK
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, jenis_mutasi, qty, created_by)
    VALUES (@O, 'CELANA', @PK, 'MASUK', 5, @U);
    INSERT INTO @hasil VALUES (4, 'jenis_item CELANA + pola_kemeja', 'DITOLAK', 'LOLOS', 'BUG: baris berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (4, 'jenis_item CELANA + pola_kemeja', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 5. TIDAK ADA kolom pola terisi harus DITOLAK
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, jenis_mutasi, qty, created_by)
    VALUES (@O, 'KEMEJA', 'MASUK', 5, @U);
    INSERT INTO @hasil VALUES (5, 'tanpa kolom pola sama sekali', 'DITOLAK', 'LOLOS', 'BUG: baris berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (5, 'tanpa kolom pola sama sekali', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 6. TERPAKAI negatif TANPA alasan harus BOLEH (pengecualian)
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, jenis_mutasi, qty, created_by)
    VALUES (@O, 'KEMEJA', @PK, 'TERPAKAI', -1, @U);
    INSERT INTO @hasil VALUES (6, 'TERPAKAI -1 tanpa alasan', 'LOLOS', 'LOLOS', 'benar: pengecualian TERPAKAI');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (6, 'TERPAKAI -1 tanpa alasan', 'LOLOS', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 7. RUSAK negatif DENGAN alasan harus BOLEH
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_celana_id, jenis_mutasi, qty, alasan, created_by)
    VALUES (@O, 'CELANA', @PC, 'RUSAK', -2, 'Kena noda oli', @U);
    INSERT INTO @hasil VALUES (7, 'RUSAK -2 dengan alasan', 'LOLOS', 'LOLOS', 'benar');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (7, 'RUSAK -2 dengan alasan', 'LOLOS', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 8. MASUK positif tanpa alasan harus BOLEH
BEGIN TRY
    INSERT INTO tni.stok_mutasi (order_id, jenis_item, pola_kemeja_id, jenis_mutasi, qty, created_by)
    VALUES (@O, 'KEMEJA', @PK, 'MASUK', 80, @U);
    INSERT INTO @hasil VALUES (8, 'MASUK +80 tanpa alasan', 'LOLOS', 'LOLOS', 'benar');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (8, 'MASUK +80 tanpa alasan', 'LOLOS', 'DITOLAK', ERROR_MESSAGE());
END CATCH

SELECT no_uji,
       uji,
       harapan,
       hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** TIDAK SESUAI ***' END AS kesimpulan,
       LEFT(pesan, 120) AS pesan
FROM @hasil
ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ',
              (SELECT COUNT(*) FROM @hasil WHERE harapan = hasil), ' dari ',
              (SELECT COUNT(*) FROM @hasil)) AS ringkasan;

ROLLBACK TRANSACTION;

-- bukti tidak ada sisa data
SELECT (SELECT COUNT(*) FROM tni.orders      WHERE order_code = 'UJI_CK_60') AS sisa_order,
       (SELECT COUNT(*) FROM tni.pola_kemeja WHERE kode = 'UJI_K')           AS sisa_pola_kemeja,
       (SELECT COUNT(*) FROM tni.pola_celana WHERE kode = 'UJI_C')           AS sisa_pola_celana,
       (SELECT COUNT(*) FROM tni.stok_mutasi)                                AS sisa_mutasi;
GO
