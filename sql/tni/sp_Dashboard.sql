-- Dashboard progres & kebutuhan size PDH TNI AD (Prompt 69).
--
-- TIDAK ADA logika status atau saldo yang ditulis ulang di sini:
--   status  -> tni.v_personel (status_progres)
--   stok    -> tni.v_stok_pola (saldo, stok_bebas)
--
-- STOK TIDAK DIBAGI PER AREA. Kebutuhan (butuh) boleh difilter per rawatan,
-- tapi saldo/stok_bebas SELALU global -- stok bersifat anonim per pola dan
-- dipakai rawatan mana pun. UI wajib menulis keterangan ini.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- PROGRES -- 2 result set: per area, lalu per satuan
-- ============================================================
-- @Bagian NULL = kedua result set (dipakai aplikasi: satu kali jalan).
-- 'AREA' / 'SATUAN' = hanya satu result set -- dipakai skrip verifikasi, karena
-- INSERT ... EXEC menolak SP yang mengembalikan lebih dari satu result set.
CREATE OR ALTER PROCEDURE tni.SIS_Dashboard_Progres
    @OrderId INT,
    @Bagian  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Bagian = NULLIF(UPPER(LTRIM(RTRIM(ISNULL(@Bagian, '')))), '');

    IF @Bagian IS NOT NULL AND @Bagian NOT IN ('AREA','SATUAN')
    BEGIN
        RAISERROR('Bagian harus AREA atau SATUAN (atau kosong untuk keduanya).', 16, 1);
        RETURN;
    END

    -- ---------- (1) per RAWATAN ----------
    -- Box gabungan (satuan_id NULL) hanya terhitung di tingkat area; itu
    -- memang benar -- box gabungan tidak dimiliki satuan mana pun.
    IF @Bagian IS NULL OR @Bagian = 'AREA'
    SELECT a.area_id        AS AreaId,
           a.area_code      AS AreaCode,
           a.area_name      AS AreaName,
           a.kota           AS Kota,
           x.Total          AS Total,
           x.BelumCetak     AS BelumCetak,
           x.Dicetak        AS Dicetak,
           x.SetJadi        AS SetJadi,
           x.MasukBox       AS MasukBox,
           x.Terkirim       AS Terkirim,
           CAST(CASE WHEN x.Total = 0 THEN 0
                     ELSE (x.MasukBox + x.Terkirim) * 100.0 / x.Total
                END AS DECIMAL(5,1)) AS PersenBox,
           CAST(CASE WHEN x.Total = 0 THEN 0
                     ELSE x.Terkirim * 100.0 / x.Total
                END AS DECIMAL(5,1)) AS PersenKirim,
           b.BoxTerbuka     AS BoxTerbuka,
           b.BoxTertutup    AS BoxTertutup,
           b.BoxTerkirim    AS BoxTerkirim
    FROM tni.area_rawatan a
    CROSS APPLY (
        SELECT COUNT(*)                                                           AS Total,
               SUM(CASE WHEN v.status_progres = 'BELUM_CETAK' THEN 1 ELSE 0 END)  AS BelumCetak,
               SUM(CASE WHEN v.status_progres = 'DICETAK'     THEN 1 ELSE 0 END)  AS Dicetak,
               SUM(CASE WHEN v.status_progres = 'SET_JADI'    THEN 1 ELSE 0 END)  AS SetJadi,
               SUM(CASE WHEN v.status_progres = 'MASUK_BOX'   THEN 1 ELSE 0 END)  AS MasukBox,
               SUM(CASE WHEN v.status_progres = 'TERKIRIM'    THEN 1 ELSE 0 END)  AS Terkirim
        FROM tni.v_personel v
        WHERE v.order_id = @OrderId AND v.area_id = a.area_id
    ) x
    CROSS APPLY (
        SELECT ISNULL(SUM(CASE WHEN bx.packed_at IS NULL                              THEN 1 ELSE 0 END), 0) AS BoxTerbuka,
               ISNULL(SUM(CASE WHEN bx.packed_at IS NOT NULL AND bx.shipped_at IS NULL THEN 1 ELSE 0 END), 0) AS BoxTertutup,
               ISNULL(SUM(CASE WHEN bx.shipped_at IS NOT NULL                          THEN 1 ELSE 0 END), 0) AS BoxTerkirim
        FROM tni.box bx
        WHERE bx.order_id = @OrderId AND bx.area_id = a.area_id AND bx.deleted_at IS NULL
    ) b
    WHERE a.order_id = @OrderId
      AND a.deleted_at IS NULL
    ORDER BY a.area_code;

    -- ---------- (2) per SATUAN ----------
    IF @Bagian IS NULL OR @Bagian = 'SATUAN'
    SELECT s.area_id        AS AreaId,
           a.area_code      AS AreaCode,
           a.area_name      AS AreaName,
           s.satuan_id      AS SatuanId,
           s.satuan_code    AS SatuanCode,
           s.satuan_name    AS SatuanName,
           x.Total          AS Total,
           x.BelumCetak     AS BelumCetak,
           x.Dicetak        AS Dicetak,
           x.SetJadi        AS SetJadi,
           x.MasukBox       AS MasukBox,
           x.Terkirim       AS Terkirim,
           CAST(CASE WHEN x.Total = 0 THEN 0
                     ELSE (x.MasukBox + x.Terkirim) * 100.0 / x.Total
                END AS DECIMAL(5,1)) AS PersenBox,
           CAST(CASE WHEN x.Total = 0 THEN 0
                     ELSE x.Terkirim * 100.0 / x.Total
                END AS DECIMAL(5,1)) AS PersenKirim,
           b.BoxTerbuka     AS BoxTerbuka,
           b.BoxTertutup    AS BoxTertutup,
           b.BoxTerkirim    AS BoxTerkirim
    FROM tni.satuan s
    JOIN tni.area_rawatan a ON a.area_id = s.area_id AND a.deleted_at IS NULL
    CROSS APPLY (
        SELECT COUNT(*)                                                           AS Total,
               SUM(CASE WHEN v.status_progres = 'BELUM_CETAK' THEN 1 ELSE 0 END)  AS BelumCetak,
               SUM(CASE WHEN v.status_progres = 'DICETAK'     THEN 1 ELSE 0 END)  AS Dicetak,
               SUM(CASE WHEN v.status_progres = 'SET_JADI'    THEN 1 ELSE 0 END)  AS SetJadi,
               SUM(CASE WHEN v.status_progres = 'MASUK_BOX'   THEN 1 ELSE 0 END)  AS MasukBox,
               SUM(CASE WHEN v.status_progres = 'TERKIRIM'    THEN 1 ELSE 0 END)  AS Terkirim
        FROM tni.v_personel v
        WHERE v.order_id = @OrderId AND v.satuan_id = s.satuan_id
    ) x
    CROSS APPLY (
        SELECT ISNULL(SUM(CASE WHEN bx.packed_at IS NULL                              THEN 1 ELSE 0 END), 0) AS BoxTerbuka,
               ISNULL(SUM(CASE WHEN bx.packed_at IS NOT NULL AND bx.shipped_at IS NULL THEN 1 ELSE 0 END), 0) AS BoxTertutup,
               ISNULL(SUM(CASE WHEN bx.shipped_at IS NOT NULL                          THEN 1 ELSE 0 END), 0) AS BoxTerkirim
        FROM tni.box bx
        WHERE bx.order_id = @OrderId AND bx.satuan_id = s.satuan_id AND bx.deleted_at IS NULL
    ) b
    WHERE a.order_id = @OrderId
      AND s.deleted_at IS NULL
    ORDER BY a.area_code, s.satuan_code;
END;
GO

-- ============================================================
-- KEBUTUHAN SIZE -- per pola, untuk memprioritaskan produksi
--
-- butuh      personel BELUM dapat set (BELUM_CETAK + DICETAK) yang memakai
--            pola ini; DIFILTER @AreaId bila diisi.
--            2026-10-07: juga DIFILTER @SatuanId bila diisi.
-- saldo      stok GLOBAL dari tni.v_stok_pola -- tidak dibagi per area.
-- stok_bebas saldo - dijatah (kartu DICETAK), juga global.
-- selisih    saldo - butuh; negatif = harus diproduksi.
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Dashboard_KebutuhanSize
    @OrderId   INT,
    @AreaId    INT = NULL,
    @SatuanId  INT = NULL,          -- 2026-10-07: filter satuan (butuh saja)
    @JenisItem VARCHAR(10) = 'KEMEJA'
AS
BEGIN
    SET NOCOUNT ON;

    SET @JenisItem = UPPER(LTRIM(RTRIM(ISNULL(@JenisItem, 'KEMEJA'))));

    IF @JenisItem NOT IN ('KEMEJA','CELANA')
    BEGIN
        RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
        RETURN;
    END

    -- Kebutuhan dihitung ULANG dari v_personel (bukan v_stok_pola.kebutuhan_sisa)
    -- karena yang itu global, sedangkan di sini boleh difilter per rawatan.
    ;WITH butuh AS (
        SELECT CASE WHEN @JenisItem = 'KEMEJA' THEN v.pola_kemeja_id
                    ELSE v.pola_celana_id END AS pola_id,
               COUNT(*)                       AS butuh
        FROM tni.v_personel v
        WHERE v.order_id = @OrderId
          AND v.status_progres IN ('BELUM_CETAK','DICETAK')
          AND (@AreaId IS NULL OR v.area_id = @AreaId)
          AND (@SatuanId IS NULL OR v.satuan_id = @SatuanId)
        GROUP BY CASE WHEN @JenisItem = 'KEMEJA' THEN v.pola_kemeja_id
                      ELSE v.pola_celana_id END
    )
    SELECT sp.pola_id          AS PolaId,
           sp.jenis_item       AS JenisItem,
           sp.kode             AS Kode,
           sp.is_active        AS IsActive,
           ISNULL(b.butuh, 0)  AS Butuh,
           sp.saldo            AS Saldo,
           sp.stok_bebas       AS StokBebas,
           sp.dijatah          AS Dijatah,
           sp.saldo - ISNULL(b.butuh, 0) AS Selisih,
           sp.grup_gender      AS GrupGender
    FROM tni.v_stok_pola sp
    LEFT JOIN butuh b ON b.pola_id = sp.pola_id
    WHERE sp.order_id = @OrderId
      AND sp.jenis_item = @JenisItem
      -- pola yang tidak dibutuhkan DAN tidak ada stoknya tidak perlu ditampilkan
      AND (ISNULL(b.butuh, 0) > 0 OR sp.saldo <> 0)
    -- 2026-10-07: sama dengan semua tampilan stok -- grup gender lalu angka pola
    -- (sebelumnya: paling kurang di atas).
    ORDER BY sp.urut_gender, sp.urut_varian, sp.urut_size, sp.kode;
END;
GO
