-- Stok kemeja & celana PDH TNI AD (Prompt 64).
--
-- Produksi menyetor bertahap TANPA nomor surat jalan. Stok ANONIM per pola.
-- Saldo selalu SUM(qty) dari tni.stok_mutasi -- lihat tni.v_stok_pola.
--
-- TERPAKAI dibuat otomatis oleh scan Set Jadi (Prompt 66) dan BONGKAR oleh
-- persetujuan pembatalan (Prompt 68). KEDUANYA TIDAK BOLEH diinput manual --
-- SIS_Stok_Manage hanya menerima MASUK / RUSAK / KOREKSI.
--
-- Tidak ada UPDATE mutasi. 2026-10-06: mutasi MANUAL (MASUK / RUSAK / KOREKSI)
-- boleh DIHAPUS (soft delete) dari tab Riwayat atas permintaan owner;
-- TERPAKAI & BONGKAR tetap tidak bisa dihapus (milik scan & pembatalan).
--
-- 2026-10-07 (alter_76): setoran punya header tni.stok_setoran, satu per
-- (order, tanggal, supplier). SETORAN dengan kunci yang sama DIGABUNG;
-- SETORAN_EDIT mengubah master + isi; SETORAN_HAPUS menghapus seluruhnya.
-- 2026-10-07 (alter_77): pengeluaran (RUSAK/KOREKSI) juga punya header
-- tni.stok_keluar, banyak pola per pengeluaran, TANPA penggabungan;
-- KELUAR_EDIT / KELUAR_HAPUS setara dengan setoran.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE tni.SIS_Stok_Manage
    @Action      VARCHAR(20),
    @OrderId     INT,
    @Tanggal     DATE = NULL,
    -- SETORAN: JSON array [{jenisItem, polaId, qty}]
    @Items       NVARCHAR(MAX) = NULL,
    -- KELUAR: item tunggal
    @JenisMutasi VARCHAR(20) = NULL,       -- RUSAK | KOREKSI
    @JenisItem   VARCHAR(10) = NULL,       -- KEMEJA | CELANA
    @PolaId      INT = NULL,
    @Qty         INT = NULL,
    @Alasan      VARCHAR(500) = NULL,
    @Supplier    VARCHAR(150) = NULL,      -- SETORAN: teks bebas, opsional
    @MutasiId    INT = NULL,               -- DELETE
    @SetoranId   INT = NULL,               -- SETORAN_EDIT / SETORAN_HAPUS (alter_76)
    @KeluarId    INT = NULL,               -- KELUAR_EDIT / KELUAR_HAPUS (alter_77)
    @Arah        INT = NULL,               -- KELUAR KOREKSI dengan @Items: 1 tambah | -1 kurangi
    @UserId      INT = NULL,
    @PerangkatId   INT = NULL      -- perangkat pelaksana (nama petugas = perangkat.nama_petugas), bukan user
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM tni.orders WHERE order_id = @OrderId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Order tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Tanggal IS NULL SET @Tanggal = CAST(SYSDATETIME() AS DATE);

    -- ========================================================
    -- SETORAN -- satu transaksi, boleh berisi kemeja DAN celana
    -- ========================================================
    IF @Action = 'SETORAN'
    BEGIN
        IF @Items IS NULL OR ISJSON(@Items) <> 1
        BEGIN
            RAISERROR('Daftar setoran tidak valid.', 16, 1);
            RETURN;
        END

        -- Satu pola hanya boleh muncul sekali per setoran: baris dobel DIGABUNG
        -- (SUM), bukan ditolak.
        SELECT j.jenisItem, j.polaId, SUM(j.qty) AS qty
        INTO #s
        FROM OPENJSON(@Items) WITH (
            jenisItem VARCHAR(10) '$.jenisItem',
            polaId    INT         '$.polaId',
            qty       INT         '$.qty'
        ) j
        GROUP BY j.jenisItem, j.polaId;

        IF NOT EXISTS (SELECT 1 FROM #s)
        BEGIN
            RAISERROR('Setoran kosong.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #s WHERE jenisItem NOT IN ('KEMEJA','CELANA'))
        BEGIN
            RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #s WHERE qty IS NULL OR qty <= 0)
        BEGIN
            RAISERROR('Jumlah setoran harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- pola harus hidup & aktif dan cocok dengan jenisItem
        DECLARE @BadKode VARCHAR(100);

        SELECT TOP 1 @BadKode = CONCAT(s.jenisItem, ' id ', s.polaId)
        FROM #s s
        WHERE (s.jenisItem = 'KEMEJA'
               AND NOT EXISTS (SELECT 1 FROM tni.pola_kemeja pk
                                WHERE pk.pola_kemeja_id = s.polaId
                                  AND pk.deleted_at IS NULL AND pk.is_active = 1))
           OR (s.jenisItem = 'CELANA'
               AND NOT EXISTS (SELECT 1 FROM tni.pola_celana pc
                                WHERE pc.pola_celana_id = s.polaId
                                  AND pc.deleted_at IS NULL AND pc.is_active = 1));

        IF @BadKode IS NOT NULL
        BEGIN
            RAISERROR('Pola tidak ditemukan atau nonaktif: %s.', 16, 1, @BadKode);
            RETURN;
        END

        SET @Supplier = NULLIF(LTRIM(RTRIM(ISNULL(@Supplier, ''))), '');

        BEGIN TRY
            BEGIN TRANSACTION;

            -- 2026-10-07 (alter_76): satu header per (order, tanggal, supplier).
            -- Sudah ada -> DIGABUNG: pola yang sama ditambah qty-nya, pola baru
            -- jadi baris baru.
            DECLARE @Digabung BIT = 0;

            SELECT @SetoranId = setoran_id
            FROM tni.stok_setoran WITH (UPDLOCK, HOLDLOCK)
            WHERE order_id = @OrderId
              AND tanggal = @Tanggal
              AND (supplier = @Supplier OR (supplier IS NULL AND @Supplier IS NULL))
              AND deleted_at IS NULL;

            IF @SetoranId IS NULL
            BEGIN
                INSERT INTO tni.stok_setoran (order_id, tanggal, supplier, perangkat_id, created_by)
                VALUES (@OrderId, @Tanggal, @Supplier, @PerangkatId, @UserId);
                SET @SetoranId = CAST(SCOPE_IDENTITY() AS INT);
            END
            ELSE
            BEGIN
                SET @Digabung = 1;
                UPDATE tni.stok_setoran
                SET updated_at = SYSDATETIME(), updated_by = @UserId
                WHERE setoran_id = @SetoranId;
            END

            -- pola yang sudah ada di setoran ini: tambah ke baris pertamanya
            UPDATE sm
            SET qty = sm.qty + s.qty,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            FROM tni.stok_mutasi sm
            JOIN #s s ON s.jenisItem = sm.jenis_item
                     AND s.polaId = COALESCE(sm.pola_kemeja_id, sm.pola_celana_id)
            WHERE sm.mutasi_id = (SELECT MIN(x.mutasi_id) FROM tni.stok_mutasi x
                                  WHERE x.setoran_id = @SetoranId
                                    AND x.deleted_at IS NULL
                                    AND x.jenis_item = sm.jenis_item
                                    AND COALESCE(x.pola_kemeja_id, x.pola_celana_id)
                                        = COALESCE(sm.pola_kemeja_id, sm.pola_celana_id));

            INSERT INTO tni.stok_mutasi
                (order_id, jenis_item, pola_kemeja_id, pola_celana_id,
                 jenis_mutasi, qty, tanggal, supplier, created_by, perangkat_id, setoran_id)
            SELECT @OrderId,
                   s.jenisItem,
                   CASE WHEN s.jenisItem = 'KEMEJA' THEN s.polaId END,
                   CASE WHEN s.jenisItem = 'CELANA' THEN s.polaId END,
                   'MASUK',
                   s.qty,
                   @Tanggal,
                   @Supplier,
                   @UserId,
                   @PerangkatId,
                   @SetoranId
            FROM #s s
            WHERE NOT EXISTS (SELECT 1 FROM tni.stok_mutasi x
                              WHERE x.setoran_id = @SetoranId
                                AND x.deleted_at IS NULL
                                AND x.jenis_item = s.jenisItem
                                AND COALESCE(x.pola_kemeja_id, x.pola_celana_id) = s.polaId);

            COMMIT TRANSACTION;

            SELECT (SELECT COUNT(*) FROM #s) AS JumlahBaris,
                   (SELECT SUM(qty) FROM #s WHERE jenisItem = 'KEMEJA') AS TotalKemeja,
                   (SELECT SUM(qty) FROM #s WHERE jenisItem = 'CELANA') AS TotalCelana,
                   @SetoranId AS SetoranId,
                   @Digabung  AS Digabung;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        RETURN;
    END

    -- ========================================================
    -- SETORAN_EDIT (2026-10-07) -- pop up: master (tanggal, supplier) + isi.
    -- @Items = isi LENGKAP yang baru [{jenisItem, polaId, qty}]:
    --   pola sama   -> qty diubah (baris pertama; baris dobel lama dihapus)
    --   pola baru   -> baris baru (harus pola aktif)
    --   pola hilang -> baris dihapus (soft)
    -- Tanggal/supplier baru yang sudah dipakai setoran LAIN ditolak (kunci unik).
    -- Saldo boleh jadi minus sesudahnya (aturan stok: tidak pernah diblok).
    -- ========================================================
    IF @Action = 'SETORAN_EDIT'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.stok_setoran
                       WHERE setoran_id = @SetoranId AND order_id = @OrderId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Setoran tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @Items IS NULL OR ISJSON(@Items) <> 1
        BEGIN
            RAISERROR('Daftar isi setoran tidak valid.', 16, 1);
            RETURN;
        END

        SELECT j.jenisItem, j.polaId, SUM(j.qty) AS qty
        INTO #e
        FROM OPENJSON(@Items) WITH (
            jenisItem VARCHAR(10) '$.jenisItem',
            polaId    INT         '$.polaId',
            qty       INT         '$.qty'
        ) j
        GROUP BY j.jenisItem, j.polaId;

        IF NOT EXISTS (SELECT 1 FROM #e)
        BEGIN
            RAISERROR('Isi setoran kosong -- untuk menghapus seluruh setoran pakai tombol Hapus.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #e WHERE jenisItem NOT IN ('KEMEJA','CELANA'))
        BEGIN
            RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #e WHERE qty IS NULL OR qty <= 0)
        BEGIN
            RAISERROR('Jumlah setoran harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- pola BARU (belum ada di setoran ini) harus hidup & aktif; pola lama
        -- yang kini nonaktif tetap boleh dipertahankan / diubah qty-nya.
        DECLARE @BadEdit VARCHAR(100);

        SELECT TOP 1 @BadEdit = CONCAT(e.jenisItem, ' id ', e.polaId)
        FROM #e e
        WHERE NOT EXISTS (SELECT 1 FROM tni.stok_mutasi x
                          WHERE x.setoran_id = @SetoranId AND x.deleted_at IS NULL
                            AND x.jenis_item = e.jenisItem
                            AND COALESCE(x.pola_kemeja_id, x.pola_celana_id) = e.polaId)
          AND ((e.jenisItem = 'KEMEJA'
                AND NOT EXISTS (SELECT 1 FROM tni.pola_kemeja pk
                                 WHERE pk.pola_kemeja_id = e.polaId
                                   AND pk.deleted_at IS NULL AND pk.is_active = 1))
            OR (e.jenisItem = 'CELANA'
                AND NOT EXISTS (SELECT 1 FROM tni.pola_celana pc
                                 WHERE pc.pola_celana_id = e.polaId
                                   AND pc.deleted_at IS NULL AND pc.is_active = 1)));

        IF @BadEdit IS NOT NULL
        BEGIN
            RAISERROR('Pola tidak ditemukan atau nonaktif: %s.', 16, 1, @BadEdit);
            RETURN;
        END

        SET @Supplier = NULLIF(LTRIM(RTRIM(ISNULL(@Supplier, ''))), '');

        IF EXISTS (SELECT 1 FROM tni.stok_setoran
                   WHERE order_id = @OrderId
                     AND setoran_id <> @SetoranId
                     AND tanggal = @Tanggal
                     AND (supplier = @Supplier OR (supplier IS NULL AND @Supplier IS NULL))
                     AND deleted_at IS NULL)
        BEGIN
            DECLARE @TglTeks VARCHAR(10) = CONVERT(VARCHAR(10), @Tanggal, 103);
            DECLARE @SupTeks VARCHAR(150) = ISNULL(@Supplier, '(tanpa supplier)');
            RAISERROR('Sudah ada setoran lain tanggal %s supplier %s -- ubah isi setoran itu saja.', 16, 1, @TglTeks, @SupTeks);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE tni.stok_setoran
            SET tanggal = @Tanggal,
                supplier = @Supplier,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE setoran_id = @SetoranId;

            -- baris lama: nomor urut per pola (baris dobel dari data lama)
            SELECT sm.mutasi_id, sm.jenis_item,
                   COALESCE(sm.pola_kemeja_id, sm.pola_celana_id) AS pola_id,
                   sm.qty,
                   ROW_NUMBER() OVER (PARTITION BY sm.jenis_item, COALESCE(sm.pola_kemeja_id, sm.pola_celana_id)
                                      ORDER BY sm.mutasi_id) AS rn
            INTO #lama
            FROM tni.stok_mutasi sm
            WHERE sm.setoran_id = @SetoranId AND sm.deleted_at IS NULL;

            -- hapus: pola yang tidak ada lagi + baris dobel
            UPDATE sm
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            FROM tni.stok_mutasi sm
            JOIN #lama l ON l.mutasi_id = sm.mutasi_id
            WHERE l.rn > 1
               OR NOT EXISTS (SELECT 1 FROM #e e WHERE e.jenisItem = l.jenis_item AND e.polaId = l.pola_id);

            -- ubah qty pola yang tetap ada
            UPDATE sm
            SET qty = e.qty,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            FROM tni.stok_mutasi sm
            JOIN #lama l ON l.mutasi_id = sm.mutasi_id AND l.rn = 1
            JOIN #e e ON e.jenisItem = l.jenis_item AND e.polaId = l.pola_id
            WHERE sm.qty <> e.qty
               OR EXISTS (SELECT 1 FROM #lama d WHERE d.jenis_item = l.jenis_item AND d.pola_id = l.pola_id AND d.rn > 1);

            -- pola baru
            INSERT INTO tni.stok_mutasi
                (order_id, jenis_item, pola_kemeja_id, pola_celana_id,
                 jenis_mutasi, qty, tanggal, supplier, created_by, perangkat_id, setoran_id)
            SELECT @OrderId,
                   e.jenisItem,
                   CASE WHEN e.jenisItem = 'KEMEJA' THEN e.polaId END,
                   CASE WHEN e.jenisItem = 'CELANA' THEN e.polaId END,
                   'MASUK', e.qty, @Tanggal, @Supplier, @UserId, @PerangkatId, @SetoranId
            FROM #e e
            WHERE NOT EXISTS (SELECT 1 FROM #lama l WHERE l.jenis_item = e.jenisItem AND l.pola_id = e.polaId);

            -- master ikut ke semua baris yang masih hidup
            UPDATE tni.stok_mutasi
            SET tanggal = @Tanggal,
                supplier = @Supplier,
                updated_at = CASE WHEN tanggal <> @Tanggal OR ISNULL(supplier, '') <> ISNULL(@Supplier, '')
                                  THEN SYSDATETIME() ELSE updated_at END,
                updated_by = CASE WHEN tanggal <> @Tanggal OR ISNULL(supplier, '') <> ISNULL(@Supplier, '')
                                  THEN @UserId ELSE updated_by END
            WHERE setoran_id = @SetoranId AND deleted_at IS NULL;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        RETURN;
    END

    -- ========================================================
    -- SETORAN_HAPUS (2026-10-07) -- satu setoran beserta seluruh isinya (soft).
    -- ========================================================
    IF @Action = 'SETORAN_HAPUS'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.stok_setoran
                       WHERE setoran_id = @SetoranId AND order_id = @OrderId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Setoran tidak ditemukan.', 16, 1);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE tni.stok_mutasi
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE setoran_id = @SetoranId AND deleted_at IS NULL;

            UPDATE tni.stok_setoran
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE setoran_id = @SetoranId;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        RETURN;
    END

    -- ========================================================
    -- KELUAR -- RUSAK atau KOREKSI. 2026-10-07 (alter_77): satu PENGELUARAN
    -- (header tni.stok_keluar) berisi banyak pola, sama seperti setoran.
    --   @Items  [{jenisItem, polaId, qty}] qty POSITIF; tanda dari arah:
    --           RUSAK selalu -1, KOREKSI pakai @Arah (1 tambah | -1 kurangi).
    --   Tanpa @Items (pemanggil lama): satu item @JenisItem/@PolaId/@Qty;
    --           RUSAK @Qty positif, KOREKSI tanda dari @Qty.
    -- Tidak digabung ke pengeluaran lain -- tiap simpan satu header.
    -- ========================================================
    IF @Action IN ('KELUAR','KELUAR_EDIT')
    BEGIN
        -- TERPAKAI & BONGKAR sengaja TIDAK bisa dipanggil dari sini.
        IF @JenisMutasi NOT IN ('RUSAK','KOREKSI')
        BEGIN
            RAISERROR('Jenis mutasi harus RUSAK atau KOREKSI.', 16, 1);
            RETURN;
        END

        IF @Action = 'KELUAR_EDIT'
           AND NOT EXISTS (SELECT 1 FROM tni.stok_keluar
                           WHERE keluar_id = @KeluarId AND order_id = @OrderId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Pengeluaran tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- COLLATE: temp table ikut collation tempdb, dibandingkan dengan kolom tni
        CREATE TABLE #k (jenisItem VARCHAR(10) COLLATE DATABASE_DEFAULT, polaId INT, qty INT);
        DECLARE @ArahPakai INT;

        IF @Items IS NOT NULL
        BEGIN
            IF ISJSON(@Items) <> 1
            BEGIN
                RAISERROR('Daftar pengeluaran tidak valid.', 16, 1);
                RETURN;
            END

            INSERT INTO #k (jenisItem, polaId, qty)
            SELECT j.jenisItem, j.polaId, SUM(j.qty)
            FROM OPENJSON(@Items) WITH (
                jenisItem VARCHAR(10) '$.jenisItem',
                polaId    INT         '$.polaId',
                qty       INT         '$.qty'
            ) j
            GROUP BY j.jenisItem, j.polaId;

            IF EXISTS (SELECT 1 FROM #k WHERE qty IS NULL OR qty <= 0)
            BEGIN
                RAISERROR('Jumlah harus lebih dari 0.', 16, 1);
                RETURN;
            END

            SET @ArahPakai = CASE WHEN @JenisMutasi = 'RUSAK' THEN -1 ELSE @Arah END;
            IF @ArahPakai IS NULL OR @ArahPakai NOT IN (1, -1)
            BEGIN
                RAISERROR('Arah koreksi harus tambah atau kurangi.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @Action = 'KELUAR_EDIT'
            BEGIN
                RAISERROR('Isi pengeluaran kosong -- untuk menghapus seluruh pengeluaran pakai tombol Hapus.', 16, 1);
                RETURN;
            END

            IF @JenisMutasi = 'RUSAK' AND (@Qty IS NULL OR @Qty <= 0)
            BEGIN
                RAISERROR('Jumlah barang rusak harus lebih dari 0.', 16, 1);
                RETURN;
            END
            IF @JenisMutasi = 'KOREKSI' AND (@Qty IS NULL OR @Qty = 0)
            BEGIN
                RAISERROR('Jumlah koreksi tidak boleh 0.', 16, 1);
                RETURN;
            END

            SET @ArahPakai = CASE WHEN @JenisMutasi = 'RUSAK' THEN -1 ELSE SIGN(@Qty) END;
            INSERT INTO #k VALUES (@JenisItem, @PolaId, ABS(@Qty));
        END

        IF NOT EXISTS (SELECT 1 FROM #k)
        BEGIN
            RAISERROR('Pengeluaran kosong.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #k WHERE jenisItem IS NULL OR jenisItem NOT IN ('KEMEJA','CELANA'))
        BEGIN
            RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
            RETURN;
        END

        SET @Alasan = NULLIF(LTRIM(RTRIM(ISNULL(@Alasan,''))),'');
        IF @Alasan IS NULL
        BEGIN
            RAISERROR('Alasan wajib diisi.', 16, 1);
            RETURN;
        END

        -- pola harus hidup & aktif; saat EDIT pola yang sudah ada di
        -- pengeluaran ini boleh dipertahankan walau kini nonaktif.
        DECLARE @BadKeluar VARCHAR(100);

        SELECT TOP 1 @BadKeluar = CONCAT(k.jenisItem, ' id ', k.polaId)
        FROM #k k
        WHERE NOT EXISTS (SELECT 1 FROM tni.stok_mutasi x
                          WHERE @Action = 'KELUAR_EDIT'
                            AND x.keluar_id = @KeluarId AND x.deleted_at IS NULL
                            AND x.jenis_item = k.jenisItem
                            AND COALESCE(x.pola_kemeja_id, x.pola_celana_id) = k.polaId)
          AND ((k.jenisItem = 'KEMEJA'
                AND NOT EXISTS (SELECT 1 FROM tni.pola_kemeja pk
                                 WHERE pk.pola_kemeja_id = k.polaId
                                   AND pk.deleted_at IS NULL AND pk.is_active = 1))
            OR (k.jenisItem = 'CELANA'
                AND NOT EXISTS (SELECT 1 FROM tni.pola_celana pc
                                 WHERE pc.pola_celana_id = k.polaId
                                   AND pc.deleted_at IS NULL AND pc.is_active = 1)));

        IF @BadKeluar IS NOT NULL
        BEGIN
            RAISERROR('Pola tidak ditemukan atau nonaktif: %s.', 16, 1, @BadKeluar);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            IF @Action = 'KELUAR'
            BEGIN
                INSERT INTO tni.stok_keluar (order_id, tanggal, jenis_mutasi, arah, alasan, perangkat_id, created_by)
                VALUES (@OrderId, @Tanggal, @JenisMutasi, @ArahPakai, @Alasan, @PerangkatId, @UserId);
                SET @KeluarId = CAST(SCOPE_IDENTITY() AS INT);
            END
            ELSE
            BEGIN
                UPDATE tni.stok_keluar
                SET tanggal = @Tanggal,
                    jenis_mutasi = @JenisMutasi,
                    arah = @ArahPakai,
                    alasan = @Alasan,
                    updated_at = SYSDATETIME(),
                    updated_by = @UserId
                WHERE keluar_id = @KeluarId;

                -- baris lama: nomor urut per pola
                SELECT sm.mutasi_id, sm.jenis_item,
                       COALESCE(sm.pola_kemeja_id, sm.pola_celana_id) AS pola_id,
                       ROW_NUMBER() OVER (PARTITION BY sm.jenis_item, COALESCE(sm.pola_kemeja_id, sm.pola_celana_id)
                                          ORDER BY sm.mutasi_id) AS rn
                INTO #lamaK
                FROM tni.stok_mutasi sm
                WHERE sm.keluar_id = @KeluarId AND sm.deleted_at IS NULL;

                -- hapus: pola yang tidak ada lagi + baris dobel
                UPDATE sm
                SET deleted_at = SYSDATETIME(), deleted_by = @UserId
                FROM tni.stok_mutasi sm
                JOIN #lamaK l ON l.mutasi_id = sm.mutasi_id
                WHERE l.rn > 1
                   OR NOT EXISTS (SELECT 1 FROM #k k WHERE k.jenisItem = l.jenis_item AND k.polaId = l.pola_id);

                -- semua baris yang tetap ada: qty, tanda, master
                UPDATE sm
                SET qty = k.qty * @ArahPakai,
                    jenis_mutasi = @JenisMutasi,
                    tanggal = @Tanggal,
                    alasan = @Alasan,
                    updated_at = SYSDATETIME(),
                    updated_by = @UserId
                FROM tni.stok_mutasi sm
                JOIN #lamaK l ON l.mutasi_id = sm.mutasi_id AND l.rn = 1
                JOIN #k k ON k.jenisItem = l.jenis_item AND k.polaId = l.pola_id;

                -- pola lama tidak ikut disisipkan lagi
                DELETE k
                FROM #k k
                JOIN #lamaK l ON l.jenis_item = k.jenisItem AND l.pola_id = k.polaId;
            END

            INSERT INTO tni.stok_mutasi
                (order_id, jenis_item, pola_kemeja_id, pola_celana_id,
                 jenis_mutasi, qty, alasan, tanggal, created_by, perangkat_id, keluar_id)
            SELECT @OrderId,
                   k.jenisItem,
                   CASE WHEN k.jenisItem = 'KEMEJA' THEN k.polaId END,
                   CASE WHEN k.jenisItem = 'CELANA' THEN k.polaId END,
                   @JenisMutasi, k.qty * @ArahPakai, @Alasan, @Tanggal, @UserId, @PerangkatId, @KeluarId
            FROM #k k;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        IF @Action = 'KELUAR'
            SELECT @KeluarId AS KeluarId,
                   (SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id = @KeluarId AND deleted_at IS NULL) AS JumlahBaris,
                   (SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id = @KeluarId AND deleted_at IS NULL) AS QtyTersimpan;
        RETURN;
    END

    -- ========================================================
    -- KELUAR_HAPUS (2026-10-07) -- satu pengeluaran beserta isinya (soft).
    -- ========================================================
    IF @Action = 'KELUAR_HAPUS'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.stok_keluar
                       WHERE keluar_id = @KeluarId AND order_id = @OrderId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Pengeluaran tidak ditemukan.', 16, 1);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE tni.stok_mutasi
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE keluar_id = @KeluarId AND deleted_at IS NULL;

            UPDATE tni.stok_keluar
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE keluar_id = @KeluarId;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        RETURN;
    END

    -- ========================================================
    -- DELETE (soft) -- 2026-10-06. HANYA mutasi manual (MASUK/RUSAK/KOREKSI)
    -- milik order ini. Saldo boleh jadi minus setelahnya (aturan stok sama:
    -- tidak pernah diblok).
    -- ========================================================
    IF @Action = 'DELETE'
    BEGIN
        DECLARE @JenisLama VARCHAR(20);

        SELECT @JenisLama = jenis_mutasi
        FROM tni.stok_mutasi
        WHERE mutasi_id = @MutasiId AND order_id = @OrderId AND deleted_at IS NULL;

        IF @JenisLama IS NULL
        BEGIN
            RAISERROR('Mutasi stok tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @JenisLama NOT IN ('MASUK','RUSAK','KOREKSI')
        BEGIN
            RAISERROR('Mutasi %s dibuat otomatis oleh scan/pembatalan -- tidak bisa dihapus.', 16, 1, @JenisLama);
            RETURN;
        END

        UPDATE tni.stok_mutasi
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE mutasi_id = @MutasiId AND deleted_at IS NULL;

        -- 2026-10-07: setoran yang isinya habis ikut dihapus headernya.
        UPDATE s
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        FROM tni.stok_setoran s
        JOIN tni.stok_mutasi sm ON sm.setoran_id = s.setoran_id AND sm.mutasi_id = @MutasiId
        WHERE s.deleted_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM tni.stok_mutasi x
                          WHERE x.setoran_id = s.setoran_id AND x.deleted_at IS NULL);

        -- 2026-10-07: pengeluaran yang isinya habis ikut dihapus headernya.
        UPDATE k
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        FROM tni.stok_keluar k
        JOIN tni.stok_mutasi sm ON sm.keluar_id = k.keluar_id AND sm.mutasi_id = @MutasiId
        WHERE k.deleted_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM tni.stok_mutasi x
                          WHERE x.keluar_id = k.keluar_id AND x.deleted_at IS NULL);

        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- ============================================================
-- SALDO -- dari tni.v_stok_pola, urut grup gender lalu angka pola
-- ============================================================
-- Urut grup gender (v_stok_pola.urut_gender), lalu angka pola, bukan abjad:
-- kemeja pakai lingkar_dada_acuan, celana pakai size_angka -- supaya LD_98
-- tidak muncul setelah LD_100.
CREATE OR ALTER PROCEDURE tni.SIS_Stok_Saldo
    @OrderId   INT,
    @JenisItem VARCHAR(10),
    @Search    VARCHAR(50) = NULL,
    @HanyaAda  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @JenisItem NOT IN ('KEMEJA','CELANA')
    BEGIN
        RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
        RETURN;
    END

    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search, ''))), '');

    SELECT v.jenis_item      AS JenisItem,
           v.pola_id         AS PolaId,
           v.kode            AS Kode,
           v.is_active       AS IsActive,
           v.masuk           AS Masuk,
           v.terpakai        AS Terpakai,
           v.keluar_lain     AS KeluarLain,
           v.bongkar         AS Bongkar,
           v.saldo           AS Saldo,
           v.dijatah         AS Dijatah,
           v.stok_bebas      AS StokBebas,
           v.kebutuhan_sisa  AS KebutuhanSisa,
           v.grup_gender     AS GrupGender
    FROM tni.v_stok_pola v
    WHERE v.order_id = @OrderId
      AND v.jenis_item = @JenisItem
      AND (@Search IS NULL OR v.kode LIKE '%' + @Search + '%')
      AND (@HanyaAda = 0 OR v.saldo <> 0)
      -- 2026-10-06 permintaan owner: pola NONAKTIF tidak ditampilkan di stok,
      -- KECUALI masih ada kebutuhan stoknya. Saldo <> 0 juga tetap tampil --
      -- barang fisiknya ada, jangan sampai "hilang" dari layar.
      AND (v.is_active = 1 OR v.kebutuhan_sisa > 0 OR v.saldo <> 0)
    -- 2026-10-07: dikelompokkan per gender (P, PG, W, WH / celana P, W) lalu angka pola.
    ORDER BY v.urut_gender, v.urut_varian, v.urut_size, v.kode;
END;
GO

-- ============================================================
-- RIWAYAT mutasi -- terbaru dulu, dengan paging
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Stok_Riwayat
    @OrderId     INT,
    @JenisItem   VARCHAR(10) = NULL,
    @PolaId      INT = NULL,
    @JenisMutasi VARCHAR(20) = NULL,
    @Dari        DATE = NULL,
    @Sampai      DATE = NULL,
    @PageNumber  INT = 1,
    @PageSize    INT = 50,
    -- 1 = hanya mutasi MANUAL (setoran & keluarkan) -- tab Riwayat, yang bisa dihapus
    @HanyaManual BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT sm.mutasi_id       AS MutasiId,
           sm.supplier        AS Supplier,
           sm.jenis_item      AS JenisItem,
           COALESCE(pk.kode, pc.kode) AS Kode,
           sm.jenis_mutasi    AS JenisMutasi,
           sm.qty             AS Qty,
           sm.alasan          AS Alasan,
           sm.tanggal         AS Tanggal,
           p.kode_ref         AS PersonelKodeRef,
           p.nama             AS PersonelNama,
           sm.created_at      AS CreatedAt,
           COALESCE(ptm.nama_petugas, u.FullName) AS CreatedByNama,
           COUNT(*) OVER ()   AS TotalCount
    FROM tni.stok_mutasi sm
    LEFT JOIN tni.pola_kemeja pk ON pk.pola_kemeja_id = sm.pola_kemeja_id
    LEFT JOIN tni.pola_celana pc ON pc.pola_celana_id = sm.pola_celana_id
    LEFT JOIN tni.personel p ON p.personel_id = sm.personel_id
    LEFT JOIN Users u ON u.Id = sm.created_by
    LEFT JOIN tni.perangkat ptm ON ptm.perangkat_id = sm.perangkat_id
    WHERE sm.order_id = @OrderId
      AND sm.deleted_at IS NULL
      AND (@JenisItem   IS NULL OR sm.jenis_item = @JenisItem)
      AND (@PolaId      IS NULL OR sm.pola_kemeja_id = @PolaId OR sm.pola_celana_id = @PolaId)
      AND (@JenisMutasi IS NULL OR sm.jenis_mutasi = @JenisMutasi)
      AND (@Dari        IS NULL OR sm.tanggal >= @Dari)
      AND (@Sampai      IS NULL OR sm.tanggal <= @Sampai)
      AND (@HanyaManual = 0 OR sm.jenis_mutasi IN ('MASUK','RUSAK','KOREKSI'))
    ORDER BY sm.mutasi_id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- RIWAYAT MANUAL (2026-10-07) -- tab Riwayat halaman Stok.
-- Satu ENTRI = satu setoran (header tni.stok_setoran) atau satu pengeluaran
-- RUSAK / KOREKSI (header tni.stok_keluar, alter_77) -- keduanya banyak pola.
-- Paging per ENTRI, terbaru dulu.
-- Hasil datar: satu baris per mutasi, dikelompokkan UI lewat (EntriTipe, EntriId);
-- isi setoran terurut Kemeja dulu lalu grup gender & angka pola (v_pola_urut).
-- @JenisMutasi: NULL semua | MASUK hanya setoran | RUSAK | KOREKSI
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Stok_RiwayatManual
    @OrderId     INT,
    @JenisMutasi VARCHAR(20) = NULL,
    @PageNumber  INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH entri AS (
        SELECT 'SETORAN' AS tipe, s.setoran_id AS entri_id, s.tanggal, s.created_at
        FROM tni.stok_setoran s
        WHERE s.order_id = @OrderId
          AND s.deleted_at IS NULL
          AND (@JenisMutasi IS NULL OR @JenisMutasi = 'MASUK')
          AND EXISTS (SELECT 1 FROM tni.stok_mutasi x
                      WHERE x.setoran_id = s.setoran_id AND x.deleted_at IS NULL)

        UNION ALL

        -- 2026-10-07 (alter_77): satu entri per header pengeluaran
        SELECT 'KELUAR', k.keluar_id, k.tanggal, k.created_at
        FROM tni.stok_keluar k
        WHERE k.order_id = @OrderId
          AND k.deleted_at IS NULL
          AND (@JenisMutasi IS NULL OR k.jenis_mutasi = @JenisMutasi)
          AND EXISTS (SELECT 1 FROM tni.stok_mutasi x
                      WHERE x.keluar_id = k.keluar_id AND x.deleted_at IS NULL)
    ),
    nomor AS (
        SELECT e.*,
               CAST(ROW_NUMBER() OVER (ORDER BY e.tanggal DESC, e.created_at DESC, e.entri_id DESC) AS INT) AS urut,
               COUNT(*) OVER () AS total
        FROM entri e
    ),
    hal AS (
        SELECT * FROM nomor
        WHERE urut >  (@PageNumber - 1) * @PageSize
          AND urut <=  @PageNumber      * @PageSize
    )
    SELECT h.tipe            AS EntriTipe,
           h.entri_id        AS EntriId,
           h.urut            AS EntriUrut,
           h.total           AS TotalEntri,
           COALESCE(s.tanggal, k.tanggal, sm.tanggal) AS Tanggal,
           COALESCE(s.supplier, sm.supplier) AS Supplier,
           COALESCE(s.created_at, k.created_at, sm.created_at) AS CreatedAt,
           COALESCE(ps.nama_petugas, us.FullName, pk2.nama_petugas, uk.FullName,
                    pm.nama_petugas, um.FullName) AS CreatedByNama,
           COALESCE(s.updated_at, k.updated_at) AS UpdatedAt,
           sm.mutasi_id      AS MutasiId,
           sm.jenis_mutasi   AS JenisMutasi,
           sm.jenis_item     AS JenisItem,
           COALESCE(sm.pola_kemeja_id, sm.pola_celana_id) AS PolaId,
           u.kode            AS Kode,
           sm.qty            AS Qty,
           COALESCE(k.alasan, sm.alasan) AS Alasan
    FROM hal h
    JOIN tni.stok_mutasi sm
      ON sm.deleted_at IS NULL
     AND ((h.tipe = 'SETORAN' AND sm.setoran_id = h.entri_id)
       OR (h.tipe = 'KELUAR'  AND sm.keluar_id  = h.entri_id))
    LEFT JOIN tni.stok_setoran s ON h.tipe = 'SETORAN' AND s.setoran_id = h.entri_id
    LEFT JOIN tni.stok_keluar k  ON h.tipe = 'KELUAR'  AND k.keluar_id  = h.entri_id
    LEFT JOIN tni.perangkat pk2  ON pk2.perangkat_id = k.perangkat_id
    LEFT JOIN Users uk           ON uk.Id = k.created_by
    LEFT JOIN tni.perangkat ps   ON ps.perangkat_id = s.perangkat_id
    LEFT JOIN Users us           ON us.Id = s.created_by
    LEFT JOIN tni.perangkat pm   ON pm.perangkat_id = sm.perangkat_id
    LEFT JOIN Users um           ON um.Id = sm.created_by
    LEFT JOIN tni.v_pola_urut u
           ON u.jenis_item = sm.jenis_item
          AND u.pola_id = COALESCE(sm.pola_kemeja_id, sm.pola_celana_id)
    ORDER BY h.urut,
             CASE sm.jenis_item WHEN 'KEMEJA' THEN 0 ELSE 1 END,
             u.urut_gender, u.urut_varian, u.urut_size, u.kode;
END;
GO
