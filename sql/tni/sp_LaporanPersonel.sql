/* =============================================================
   PDH TNI AD -- Laporan Personel & Box (Prompt 89)

   tni.SIS_LaporanPersonel -- sumber PDF A4 landscape "Laporan Personel & Box"
   yang diunduh dari /tni/personel.

   Parameter = filter SIS_Personel_List (tanpa paging), supaya PDF berisi
   persis daftar yang sedang tampil. Status & box SELALU dari tni.v_personel;
   box_no diambil dari tni.box (kolom alter_72, nomor urut box dalam order).

   3 result set:
     1. header  -- judul order, rawatan/satuan yang difilter, total baris
     2. baris   -- personel urut satuan_code, kode_ref (box NULL = belum masuk box)
     3. rekap   -- box yang berisi personel lingkup ini, dengan isi total &
                   isi dari lingkup ini; urut Terkirim -> Tertutup -> Terbuka, box_code

   Status box diturunkan dari packed_at / shipped_at (sama dengan SIS_Box_List).

   ANSI_NULLS / QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE tni.SIS_LaporanPersonel
    @OrderId     INT,
    @Search      VARCHAR(150) = NULL,
    @AreaId      INT = NULL,
    @SatuanId    INT = NULL,
    @Status      VARCHAR(20) = NULL,
    @PerluReview BIT = 0,
    @PolaKemejaId INT = NULL,
    @PolaCelanaId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search, ''))), '');

    -- filter SAMA PERSIS dengan SIS_Personel_List
    SELECT v.personel_id,
           v.kode_ref,
           v.satuan_id,
           v.satuan_code,
           v.satuan_name,
           v.pangkat,
           v.nama,
           v.nrp,
           v.no_hp,
           v.gender,
           v.pola_kemeja_kode,
           v.pola_celana_kode,
           v.box_id,
           v.box_code
    INTO #f
    FROM tni.v_personel v
    WHERE v.order_id = @OrderId
      AND (@AreaId   IS NULL OR v.area_id   = @AreaId)
      AND (@SatuanId IS NULL OR v.satuan_id = @SatuanId)
      AND (@Status   IS NULL OR v.status_progres = @Status)
      AND (@PerluReview = 0 OR v.status_data = 'PERLU_REVIEW')
      AND (@PolaKemejaId IS NULL OR v.pola_kemeja_id = @PolaKemejaId)
      AND (@PolaCelanaId IS NULL OR v.pola_celana_id = @PolaCelanaId)
      AND (@Search IS NULL
           OR v.kode_ref LIKE @Search + '%'
           OR v.nrp      LIKE @Search + '%'
           OR v.nama     LIKE '%' + @Search + '%');

    -- (1) header. Rawatan diisi juga saat hanya satuan yang difilter
    --     (rawatan milik satuan itu), supaya kepala PDF tetap lengkap.
    SELECT o.order_name                              AS OrderName,
           o.instansi                                AS Instansi,
           COALESCE(af.area_code, asat.area_code)    AS AreaCode,
           COALESCE(af.area_name, asat.area_name)    AS AreaName,
           s.satuan_code                             AS SatuanCode,
           s.satuan_name                             AS SatuanName,
           (SELECT COUNT(*) FROM #f)                 AS TotalBaris,
           (SELECT COUNT(DISTINCT satuan_id) FROM #f) AS JumlahSatuan,
           -- kode pola yang difilter (untuk keterangan filter di kepala PDF)
           (SELECT kode FROM tni.pola_kemeja WHERE pola_kemeja_id = @PolaKemejaId) AS PolaKemejaKode,
           (SELECT kode FROM tni.pola_celana WHERE pola_celana_id = @PolaCelanaId) AS PolaCelanaKode
    FROM tni.orders o
    LEFT JOIN tni.area_rawatan af   ON af.area_id = @AreaId
    LEFT JOIN tni.satuan s          ON s.satuan_id = @SatuanId
    LEFT JOIN tni.area_rawatan asat ON asat.area_id = s.area_id
    WHERE o.order_id = @OrderId;

    -- (2) baris personel
    SELECT f.kode_ref          AS KodeRef,
           f.satuan_code       AS SatuanCode,
           f.satuan_name       AS SatuanName,
           f.pangkat           AS Pangkat,
           f.nama              AS Nama,
           f.nrp               AS Nrp,
           f.no_hp             AS NoHp,
           f.gender            AS Gender,
           f.pola_kemeja_kode  AS PolaKemejaKode,
           f.pola_celana_kode  AS PolaCelanaKode,
           b.box_no            AS BoxNo,
           f.box_code          AS BoxCode
    FROM #f f
    LEFT JOIN tni.box b
      ON b.box_id = f.box_id
     AND b.deleted_at IS NULL
    ORDER BY f.satuan_code, f.kode_ref;

    -- (3) rekap box lingkup ini
    SELECT b.box_no                                   AS BoxNo,
           b.box_code                                 AS BoxCode,
           CAST(CASE WHEN b.satuan_id IS NULL THEN 1 ELSE 0 END AS BIT) AS Gabungan,
           CASE WHEN b.shipped_at IS NOT NULL THEN 'TERKIRIM'
                WHEN b.packed_at  IS NOT NULL THEN 'TERTUTUP'
                ELSE 'TERBUKA' END                    AS Status,
           x.isi                                      AS Isi,
           l.isi_dari_lingkup                         AS IsiDariLingkup,
           b.packed_at                                AS PackedAt,
           b.shipped_at                               AS ShippedAt
    FROM (SELECT box_id, COUNT(*) AS isi_dari_lingkup
          FROM #f
          WHERE box_id IS NOT NULL
          GROUP BY box_id) l
    JOIN tni.box b
      ON b.box_id = l.box_id
     AND b.deleted_at IS NULL
    CROSS APPLY (
        SELECT COUNT(*) AS isi
        FROM tni.personel p
        WHERE p.box_id = b.box_id AND p.deleted_at IS NULL
    ) x
    ORDER BY CASE WHEN b.shipped_at IS NOT NULL THEN 1
                  WHEN b.packed_at  IS NOT NULL THEN 2
                  ELSE 3 END,
             b.box_code;
END;
GO
