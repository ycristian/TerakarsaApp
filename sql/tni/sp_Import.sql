-- Import data personel PDH TNI AD dari export Google Form (Prompt 62).
--
-- Alur DUA LANGKAH: Unggah (SIS_Import_Stage -> staging + validasi) lalu
-- Simpan (SIS_Import_Commit -> tni.personel). Baris bermasalah TIDAK dibuang
-- diam-diam -- ditahan di staging dengan alasannya.
--
-- Pembagian tugas: API hanya memetakan header Excel & membersihkan tipe data
-- (termasuk normalisasi gender). SELURUH aturan validasi ada di SP ini.
--
-- Aturan minimal yang disepakati owner: NRP + Nama + pola kemeja + pola celana
-- wajib ada. Ukuran badan boleh kosong (±1/3 personel kategori TU_SIZING tidak
-- hadir pengukuran) dan rentangnya TIDAK divalidasi.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- STAGE -- masukkan ke staging + jalankan seluruh validasi
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Import_Stage
    @OrderId  INT,
    @NamaFile VARCHAR(255),
    @Rows     NVARCHAR(MAX),     -- JSON array hasil parsing API
    @UserId   INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM tni.orders WHERE order_id = @OrderId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Order tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Rows IS NULL OR ISJSON(@Rows) <> 1
    BEGIN
        RAISERROR('Data baris tidak valid (bukan JSON).', 16, 1);
        RETURN;
    END

    -- ---------- baris mentah dari API ----------
    -- j.value = objek baris apa adanya, disimpan ke raw_json untuk arsip.
    SELECT CAST(j.value AS NVARCHAR(MAX)) AS raw_json,
           r.*
    INTO #r
    FROM OPENJSON(@Rows) j
    CROSS APPLY OPENJSON(j.value) WITH (
        barisKe                 INT           '$.barisKe',
        submittedAt             DATETIME2     '$.submittedAt',
        emailPengisi            VARCHAR(150)  '$.emailPengisi',
        gender                  VARCHAR(20)   '$.gender',
        pangkat                 VARCHAR(50)   '$.pangkat',
        nama                    VARCHAR(150)  '$.nama',
        nrp                     VARCHAR(30)   '$.nrp',
        noHp                    VARCHAR(30)   '$.noHp',
        tinggiBadan             INT           '$.tinggiBadan',
        beratBadan              INT           '$.beratBadan',
        sizeBajuIsian           VARCHAR(30)   '$.sizeBajuIsian',
        sizeCelanaIsian         VARCHAR(30)   '$.sizeCelanaIsian',
        kategori                VARCHAR(20)   '$.kategori',
        areaName                VARCHAR(150)  '$.areaName',
        satuanName              VARCHAR(150)  '$.satuanName',
        kodeKemeja              VARCHAR(30)   '$.kodeKemeja',
        kodeCelana              VARCHAR(30)   '$.kodeCelana',
        lingkarLeher            DECIMAL(5,1)  '$.lingkarLeher',
        lebarBahu               DECIMAL(5,1)  '$.lebarBahu',
        lingkarDada             DECIMAL(5,1)  '$.lingkarDada',
        lingkarPerut            DECIMAL(5,1)  '$.lingkarPerut',
        panjangBadanDepan       DECIMAL(5,1)  '$.panjangBadanDepan',
        panjangLengan           DECIMAL(5,1)  '$.panjangLengan',
        lingkarLengan           DECIMAL(5,1)  '$.lingkarLengan',
        lingkarKetiak           DECIMAL(5,1)  '$.lingkarKetiak',
        lingkarPinggangCelana   DECIMAL(5,1)  '$.lingkarPinggangCelana',
        lingkarPinggul          DECIMAL(5,1)  '$.lingkarPinggul',
        lingkarPesak            DECIMAL(5,1)  '$.lingkarPesak',
        lingkarPaha             DECIMAL(5,1)  '$.lingkarPaha',
        lingkarLutut            DECIMAL(5,1)  '$.lingkarLutut',
        lingkarCelanaBawah      DECIMAL(5,1)  '$.lingkarCelanaBawah',
        panjangCelana           DECIMAL(5,1)  '$.panjangCelana'
    ) r;

    -- rapikan teks kunci (API sudah membersihkan; diulang supaya SP aman dipanggil langsung)
    UPDATE #r
    SET nrp  = LTRIM(RTRIM(ISNULL(nrp, ''))),
        nama = LTRIM(RTRIM(ISNULL(nama, '')));

    -- ---------- buat batch ----------
    -- SATU TRANSAKSI: kalau validasi/penulisan staging gagal di tengah jalan,
    -- jangan tinggalkan baris batch yatim (jumlah_baris 0, tanpa staging).
    DECLARE @BatchId INT;

    BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO tni.import_batch (order_id, nama_file, jumlah_baris, created_by)
    VALUES (@OrderId, @NamaFile, (SELECT COUNT(*) FROM #r), @UserId);

    SET @BatchId = CAST(SCOPE_IDENTITY() AS INT);

    -- ---------- NRP kembar DI DALAM FILE YANG SAMA ----------
    -- Semua baris NRP itu ditolak, pesannya menyebut nomor baris yang bentrok.
    SELECT nrp,
           STRING_AGG(CAST(barisKe AS VARCHAR(10)), ', ') WITHIN GROUP (ORDER BY barisKe) AS baris_bentrok,
           COUNT(*) AS jml
    INTO #dup
    FROM #r
    WHERE nrp <> ''
    GROUP BY nrp
    HAVING COUNT(*) > 1;

    -- ---------- resolusi master + personel yang sudah ada ----------
    SELECT r.barisKe,
           r.raw_json,
           r.nrp,
           r.nama,
           a.area_id,
           s.satuan_id,
           pk.pola_kemeja_id,
           pk.target_gender          AS gender_pola_kemeja,
           pc.pola_celana_id,
           p.personel_id             AS existing_id,
           p.satuan_id               AS existing_satuan_id,
           p.set_at                  AS existing_set_at,
           p.pola_kemeja_id          AS existing_pola_kemeja_id,
           pkx.kode                  AS existing_kode_kemeja,
           p.pola_celana_id          AS existing_pola_celana_id,
           pcx.kode                  AS existing_kode_celana,
           d.baris_bentrok
    INTO #res
    FROM #r r
    LEFT JOIN tni.area_rawatan a
           ON a.order_id = @OrderId AND a.area_name = r.areaName AND a.deleted_at IS NULL
    LEFT JOIN tni.satuan s
           ON s.area_id = a.area_id AND s.satuan_name = r.satuanName AND s.deleted_at IS NULL
    -- pola harus HIDUP dan AKTIF; nonaktif diperlakukan sama dengan tidak dikenal
    LEFT JOIN tni.pola_kemeja pk
           ON pk.kode = r.kodeKemeja AND pk.deleted_at IS NULL AND pk.is_active = 1
    LEFT JOIN tni.pola_celana pc
           ON pc.kode = r.kodeCelana AND pc.deleted_at IS NULL AND pc.is_active = 1
    LEFT JOIN tni.personel p
           ON p.order_id = @OrderId AND p.nrp = r.nrp AND p.deleted_at IS NULL
    LEFT JOIN tni.pola_kemeja pkx ON pkx.pola_kemeja_id = p.pola_kemeja_id
    LEFT JOIN tni.pola_celana pcx ON pcx.pola_celana_id = p.pola_celana_id
    LEFT JOIN #dup d ON d.nrp = r.nrp;

    -- ---------- hitung hasil validasi ----------
    -- TOLAK diperiksa berurutan (pesan pertama yang kena dipakai).
    -- REVIEW boleh menumpuk beberapa alasan.
    SELECT r.barisKe,
           r.raw_json,
           r.nrp,
           r.nama,
           res.existing_id,
           CASE
               WHEN r.nrp = '' OR r.nama = ''        THEN 'TOLAK'
               WHEN res.area_id IS NULL              THEN 'TOLAK'
               WHEN res.satuan_id IS NULL            THEN 'TOLAK'
               WHEN res.pola_kemeja_id IS NULL       THEN 'TOLAK'
               WHEN res.pola_celana_id IS NULL       THEN 'TOLAK'
               WHEN res.baris_bentrok IS NOT NULL    THEN 'TOLAK'
               ELSE 'LANJUT'
           END AS tahap1,
           CASE
               WHEN r.nrp = '' AND r.nama = ''  THEN 'NRP dan Nama kosong.'
               WHEN r.nrp = ''                  THEN 'NRP kosong.'
               WHEN r.nama = ''                 THEN 'Nama kosong.'
               WHEN res.area_id IS NULL         THEN CONCAT('Area Rawatan tidak dikenal: "', ISNULL(r.areaName,''), '".')
               WHEN res.satuan_id IS NULL       THEN CONCAT('Satuan tidak dikenal di area tersebut: "', ISNULL(r.satuanName,''), '".')
               WHEN res.pola_kemeja_id IS NULL  THEN CONCAT('Pola kemeja tidak ada di master / nonaktif: "', ISNULL(r.kodeKemeja,''), '".')
               WHEN res.pola_celana_id IS NULL  THEN CONCAT('Pola celana tidak ada di master / nonaktif: "', ISNULL(r.kodeCelana,''), '".')
               WHEN res.baris_bentrok IS NOT NULL THEN CONCAT('NRP kembar di file ini (baris ', res.baris_bentrok, ').')
               ELSE NULL
           END AS pesan_tolak,
           -- REVIEW 1: NRP terlalu pendek
           CASE WHEN r.nrp <> '' AND LEN(r.nrp) < 12
                THEN CONCAT('NRP hanya ', LEN(r.nrp), ' digit, umumnya 13-16.')
           END AS pesan_nrp,
           -- REVIEW 2: gender bentrok dengan kelompok pola kemeja
           -- (P/PG = pria, W/W_PG = wanita non-hijab, WH/WH_PG = wanita hijab)
           CASE
               WHEN res.gender_pola_kemeja IS NULL THEN NULL
               WHEN r.gender = 'PRIA'             AND res.gender_pola_kemeja NOT IN ('P','PG')
                    THEN CONCAT('Gender PRIA tapi pola kemeja ', r.kodeKemeja, ' untuk wanita -- beda lengan pendek/panjang, cek.')
               WHEN r.gender = 'WANITA_NON_HIJAB' AND res.gender_pola_kemeja NOT IN ('W','W_PG')
                    THEN CONCAT('Gender WANITA NON HIJAB tapi pola kemeja ', r.kodeKemeja, ' bukan pola itu -- beda lengan pendek/panjang, cek.')
               WHEN r.gender = 'WANITA_HIJAB'     AND res.gender_pola_kemeja NOT IN ('WH','WH_PG')
                    THEN CONCAT('Gender WANITA HIJAB tapi pola kemeja ', r.kodeKemeja, ' bukan pola hijab -- beda lengan pendek/panjang, cek.')
               ELSE NULL
           END AS pesan_gender,
           -- REVIEW 3: sudah SET JADI tapi pola di file berbeda -> pola TIDAK diubah
           CASE
               WHEN res.existing_id IS NOT NULL AND res.existing_set_at IS NOT NULL
                AND res.pola_kemeja_id IS NOT NULL AND res.existing_pola_kemeja_id <> res.pola_kemeja_id
                    THEN CONCAT('Pola kemeja berubah setelah set jadi: ', res.existing_kode_kemeja, ' -> ', r.kodeKemeja, ' (tidak diubah).')
           END AS pesan_set_kemeja,
           CASE
               WHEN res.existing_id IS NOT NULL AND res.existing_set_at IS NOT NULL
                AND res.pola_celana_id IS NOT NULL AND res.existing_pola_celana_id <> res.pola_celana_id
                    THEN CONCAT('Pola celana berubah setelah set jadi: ', res.existing_kode_celana, ' -> ', r.kodeCelana, ' (tidak diubah).')
           END AS pesan_set_celana,
           -- REVIEW 4: satuan di file beda dengan satuan personel lama -> JANGAN dipindahkan
           CASE
               WHEN res.existing_id IS NOT NULL AND res.satuan_id IS NOT NULL
                AND res.existing_satuan_id <> res.satuan_id
                    THEN CONCAT('Satuan di file beda dengan data lama: "', r.satuanName, '" (tidak dipindahkan).')
           END AS pesan_satuan
    INTO #val
    FROM #r r
    JOIN #res res ON res.barisKe = r.barisKe;

    -- ---------- tulis ke staging ----------
    INSERT INTO tni.import_staging
        (batch_id, baris_ke, nrp, nama, raw_json, hasil_validasi, aksi, pesan_error, created_by)
    SELECT @BatchId,
           v.barisKe,
           NULLIF(v.nrp, ''),
           NULLIF(v.nama, ''),
           v.raw_json,
           CASE
               WHEN v.tahap1 = 'TOLAK' THEN 'TOLAK'
               WHEN COALESCE(v.pesan_nrp, v.pesan_gender, v.pesan_set_kemeja,
                             v.pesan_set_celana, v.pesan_satuan) IS NOT NULL THEN 'REVIEW'
               ELSE 'VALID'
           END,
           CASE
               WHEN v.tahap1 = 'TOLAK' THEN NULL
               WHEN v.existing_id IS NOT NULL THEN 'PERBARUI'
               ELSE 'BARU'
           END,
           CASE
               WHEN v.tahap1 = 'TOLAK' THEN LEFT(v.pesan_tolak, 1000)
               ELSE LEFT(NULLIF(CONCAT_WS(' ',
                        v.pesan_nrp, v.pesan_gender, v.pesan_set_kemeja,
                        v.pesan_set_celana, v.pesan_satuan), ''), 1000)
           END,
           @UserId
    FROM #val v;

    -- ---------- hitungan di batch ----------
    UPDATE b
    SET jumlah_baru       = x.baru,
        jumlah_diperbarui = x.diperbarui,
        jumlah_review     = x.review,
        jumlah_ditolak    = x.ditolak
    FROM tni.import_batch b
    CROSS APPLY (
        SELECT
            -- Baru/Diperbarui dihitung dari baris yang AKAN disimpan (VALID + REVIEW)
            SUM(CASE WHEN st.hasil_validasi <> 'TOLAK' AND st.aksi = 'BARU'     THEN 1 ELSE 0 END) AS baru,
            SUM(CASE WHEN st.hasil_validasi <> 'TOLAK' AND st.aksi = 'PERBARUI' THEN 1 ELSE 0 END) AS diperbarui,
            SUM(CASE WHEN st.hasil_validasi = 'REVIEW' THEN 1 ELSE 0 END) AS review,
            SUM(CASE WHEN st.hasil_validasi = 'TOLAK'  THEN 1 ELSE 0 END) AS ditolak
        FROM tni.import_staging st
        WHERE st.batch_id = @BatchId
    ) x
    WHERE b.batch_id = @BatchId;

    COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @BatchId AS BatchId;
END;
GO

-- ============================================================
-- GET BATCH -- 2 result set: ringkasan + baris bermasalah
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Import_GetBatch
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.batch_id          AS BatchId,
           b.order_id          AS OrderId,
           b.nama_file         AS NamaFile,
           b.jumlah_baris      AS JumlahBaris,
           b.jumlah_baru       AS JumlahBaru,
           b.jumlah_diperbarui AS JumlahDiperbarui,
           b.jumlah_review     AS JumlahReview,
           b.jumlah_ditolak    AS JumlahDitolak,
           b.committed_at      AS CommittedAt,
           u.FullName          AS CommittedByNama,
           b.catatan           AS Catatan,
           b.created_at        AS CreatedAt,
           cu.FullName         AS CreatedByNama
    FROM tni.import_batch b
    LEFT JOIN Users u  ON u.Id = b.committed_by
    LEFT JOIN Users cu ON cu.Id = b.created_by
    WHERE b.batch_id = @BatchId AND b.deleted_at IS NULL;

    SELECT st.baris_ke       AS BarisKe,
           st.nrp            AS Nrp,
           st.nama           AS Nama,
           st.hasil_validasi AS Hasil,
           st.aksi           AS Aksi,
           st.pesan_error    AS Pesan
    FROM tni.import_staging st
    WHERE st.batch_id = @BatchId
      AND st.hasil_validasi IN ('TOLAK','REVIEW')
    ORDER BY CASE st.hasil_validasi WHEN 'TOLAK' THEN 0 ELSE 1 END, st.baris_ke;
END;
GO

-- ============================================================
-- BATCH LIST -- riwayat import, terbaru dulu
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Import_BatchList
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.batch_id          AS BatchId,
           b.nama_file         AS NamaFile,
           b.jumlah_baris      AS JumlahBaris,
           b.jumlah_baru       AS JumlahBaru,
           b.jumlah_diperbarui AS JumlahDiperbarui,
           b.jumlah_review     AS JumlahReview,
           b.jumlah_ditolak    AS JumlahDitolak,
           b.committed_at      AS CommittedAt,
           u.FullName          AS CommittedByNama,
           b.created_at        AS CreatedAt,
           cu.FullName         AS CreatedByNama
    FROM tni.import_batch b
    LEFT JOIN Users u  ON u.Id = b.committed_by
    LEFT JOIN Users cu ON cu.Id = b.created_by
    WHERE b.order_id = @OrderId AND b.deleted_at IS NULL
    ORDER BY b.batch_id DESC;
END;
GO

-- ============================================================
-- COMMIT -- simpan staging ke tni.personel (SATU TRANSAKSI)
-- ============================================================
-- Yang TIDAK pernah diubah untuk personel lama: kode_ref, no_urut, qr_token,
-- dan satuan. Personel yang ada di database tapi tidak ada di file TIDAK
-- disentuh (import tidak pernah menghapus).
CREATE OR ALTER PROCEDURE tni.SIS_Import_Commit
    @BatchId INT,
    @UserId  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @OrderId INT, @CommittedAt DATETIME2;

    SELECT @OrderId = order_id, @CommittedAt = committed_at
    FROM tni.import_batch
    WHERE batch_id = @BatchId AND deleted_at IS NULL;

    IF @OrderId IS NULL
    BEGIN
        RAISERROR('Batch import tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @CommittedAt IS NOT NULL
    BEGIN
        RAISERROR('Batch ini sudah pernah disimpan.', 16, 1);
        RETURN;
    END

    -- baris yang akan disimpan: VALID + REVIEW (TOLAK ditahan)
    SELECT st.staging_id,
           st.baris_ke,
           st.aksi,
           st.hasil_validasi,
           st.pesan_error,
           r.*
    INTO #c
    FROM tni.import_staging st
    CROSS APPLY OPENJSON(st.raw_json) WITH (
        submittedAt             DATETIME2     '$.submittedAt',
        emailPengisi            VARCHAR(150)  '$.emailPengisi',
        gender                  VARCHAR(20)   '$.gender',
        pangkat                 VARCHAR(50)   '$.pangkat',
        nama                    VARCHAR(150)  '$.nama',
        nrp                     VARCHAR(30)   '$.nrp',
        noHp                    VARCHAR(30)   '$.noHp',
        tinggiBadan             INT           '$.tinggiBadan',
        beratBadan              INT           '$.beratBadan',
        sizeBajuIsian           VARCHAR(30)   '$.sizeBajuIsian',
        sizeCelanaIsian         VARCHAR(30)   '$.sizeCelanaIsian',
        kategori                VARCHAR(20)   '$.kategori',
        areaName                VARCHAR(150)  '$.areaName',
        satuanName              VARCHAR(150)  '$.satuanName',
        kodeKemeja              VARCHAR(30)   '$.kodeKemeja',
        kodeCelana              VARCHAR(30)   '$.kodeCelana',
        lingkarLeher            DECIMAL(5,1)  '$.lingkarLeher',
        lebarBahu               DECIMAL(5,1)  '$.lebarBahu',
        lingkarDada             DECIMAL(5,1)  '$.lingkarDada',
        lingkarPerut            DECIMAL(5,1)  '$.lingkarPerut',
        panjangBadanDepan       DECIMAL(5,1)  '$.panjangBadanDepan',
        panjangLengan           DECIMAL(5,1)  '$.panjangLengan',
        lingkarLengan           DECIMAL(5,1)  '$.lingkarLengan',
        lingkarKetiak           DECIMAL(5,1)  '$.lingkarKetiak',
        lingkarPinggangCelana   DECIMAL(5,1)  '$.lingkarPinggangCelana',
        lingkarPinggul          DECIMAL(5,1)  '$.lingkarPinggul',
        lingkarPesak            DECIMAL(5,1)  '$.lingkarPesak',
        lingkarPaha             DECIMAL(5,1)  '$.lingkarPaha',
        lingkarLutut            DECIMAL(5,1)  '$.lingkarLutut',
        lingkarCelanaBawah      DECIMAL(5,1)  '$.lingkarCelanaBawah',
        panjangCelana           DECIMAL(5,1)  '$.panjangCelana'
    ) r
    WHERE st.batch_id = @BatchId
      AND st.hasil_validasi IN ('VALID','REVIEW');

    -- resolusi id master + personel lama
    -- COLLATE DATABASE_DEFAULT wajib di kolom teks yang DITAMBAHKAN ke tabel temp:
    -- collation tempdb di server ini (Latin1_General_CI_AS) BEDA dengan collation
    -- database (SQL_Latin1_General_CP1_CI_AS), jadi tanpa ini perbandingan dengan
    -- kolom tni.* gagal "Cannot resolve the collation conflict".
    ALTER TABLE #c ADD satuan_id INT, pola_kemeja_id INT, pola_celana_id INT,
                       existing_id INT, existing_set_at DATETIME2,
                       satuan_code VARCHAR(10) COLLATE DATABASE_DEFAULT;

    UPDATE c
    SET satuan_id       = s.satuan_id,
        satuan_code     = s.satuan_code,
        pola_kemeja_id  = pk.pola_kemeja_id,
        pola_celana_id  = pc.pola_celana_id,
        existing_id     = p.personel_id,
        existing_set_at = p.set_at
    FROM #c c
    LEFT JOIN tni.area_rawatan a
           ON a.order_id = @OrderId AND a.area_name = c.areaName AND a.deleted_at IS NULL
    LEFT JOIN tni.satuan s
           ON s.area_id = a.area_id AND s.satuan_name = c.satuanName AND s.deleted_at IS NULL
    LEFT JOIN tni.pola_kemeja pk
           ON pk.kode = c.kodeKemeja AND pk.deleted_at IS NULL AND pk.is_active = 1
    LEFT JOIN tni.pola_celana pc
           ON pc.kode = c.kodeCelana AND pc.deleted_at IS NULL AND pc.is_active = 1
    LEFT JOIN tni.personel p
           ON p.order_id = @OrderId AND p.nrp = c.nrp AND p.deleted_at IS NULL;

    DECLARE @Baru INT = 0, @Perbarui INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ============ 1. PERBARUI personel yang sudah ada ============
        -- kode_ref / no_urut / qr_token / satuan_id SENGAJA tidak ada di SET ini.
        -- Pola hanya diubah bila belum set jadi (set_at IS NULL).
        UPDATE p
        SET pangkat                 = c.pangkat,
            nama                    = c.nama,
            no_hp                   = c.noHp,
            gender                  = c.gender,
            tinggi_badan            = c.tinggiBadan,
            berat_badan             = c.beratBadan,
            kategori                = c.kategori,
            pola_kemeja_id          = CASE WHEN p.set_at IS NULL THEN c.pola_kemeja_id ELSE p.pola_kemeja_id END,
            pola_celana_id          = CASE WHEN p.set_at IS NULL THEN c.pola_celana_id ELSE p.pola_celana_id END,
            size_baju_isian         = c.sizeBajuIsian,
            size_celana_isian       = c.sizeCelanaIsian,
            email_pengisi           = c.emailPengisi,
            submitted_at            = c.submittedAt,
            lingkar_leher           = c.lingkarLeher,
            lebar_bahu              = c.lebarBahu,
            lingkar_dada            = c.lingkarDada,
            lingkar_perut           = c.lingkarPerut,
            panjang_badan_depan     = c.panjangBadanDepan,
            panjang_lengan          = c.panjangLengan,
            lingkar_lengan          = c.lingkarLengan,
            lingkar_ketiak          = c.lingkarKetiak,
            lingkar_pinggang_celana = c.lingkarPinggangCelana,
            lingkar_pinggul         = c.lingkarPinggul,
            lingkar_pesak           = c.lingkarPesak,
            lingkar_paha            = c.lingkarPaha,
            lingkar_lutut           = c.lingkarLutut,
            lingkar_celana_bawah    = c.lingkarCelanaBawah,
            panjang_celana          = c.panjangCelana,
            status_data             = CASE WHEN c.hasil_validasi = 'REVIEW' THEN 'PERLU_REVIEW' ELSE p.status_data END,
            catatan_review          = CASE WHEN c.hasil_validasi = 'REVIEW' THEN c.pesan_error ELSE p.catatan_review END,
            updated_at              = SYSDATETIME(),
            updated_by              = @UserId
        FROM tni.personel p
        JOIN #c c ON c.existing_id = p.personel_id
        WHERE c.aksi = 'PERBARUI' AND p.deleted_at IS NULL;

        SET @Perbarui = @@ROWCOUNT;

        -- ============ 2. BARU ============
        SELECT c.staging_id,
               c.satuan_id,
               c.satuan_code,
               -- Urutan pemberian nomor: submitted_at lalu baris_ke.
               ROW_NUMBER() OVER (PARTITION BY c.satuan_id
                                  ORDER BY c.submittedAt, c.baris_ke) AS urut_dalam_batch
        INTO #baru
        FROM #c c
        WHERE c.aksi = 'BARU' AND c.satuan_id IS NOT NULL;

        IF EXISTS (SELECT 1 FROM #baru)
        BEGIN
            -- Kunci per satuan supaya dua import bersamaan tidak dapat nomor sama.
            DECLARE @sid INT, @lockName VARCHAR(100), @rc INT;
            DECLARE satuan_cur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT satuan_id FROM #baru ORDER BY satuan_id;

            OPEN satuan_cur;
            FETCH NEXT FROM satuan_cur INTO @sid;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @lockName = CONCAT('tni_personel_no_urut_', @sid);
                EXEC @rc = sp_getapplock @Resource = @lockName, @LockMode = 'Exclusive',
                                         @LockOwner = 'Transaction', @LockTimeout = 15000;
                IF @rc < 0
                BEGIN
                    CLOSE satuan_cur; DEALLOCATE satuan_cur;
                    RAISERROR('Gagal mengunci penomoran satuan %d -- coba lagi.', 16, 1, @sid);
                    ROLLBACK TRANSACTION;
                    RETURN;
                END
                FETCH NEXT FROM satuan_cur INTO @sid;
            END
            CLOSE satuan_cur;
            DEALLOCATE satuan_cur;

            -- no_urut = MAX yang sudah ada (TERMASUK baris terhapus, supaya nomor
            -- tidak pernah didaur ulang) + urutan dalam batch.
            SELECT b.staging_id,
                   b.satuan_id,
                   b.satuan_code,
                   ISNULL(mx.max_urut, 0) + b.urut_dalam_batch AS no_urut
            INTO #nomor
            FROM #baru b
            OUTER APPLY (
                SELECT MAX(p.no_urut) AS max_urut
                FROM tni.personel p
                WHERE p.satuan_id = b.satuan_id
            ) mx;

            -- kode_ref: 3 digit; lebih dari 999 dibiarkan 4 digit.
            -- COLLATE DATABASE_DEFAULT: lihat catatan di ALTER TABLE #c di atas.
            ALTER TABLE #nomor ADD kode_ref VARCHAR(30) COLLATE DATABASE_DEFAULT,
                                   qr_token VARCHAR(16) COLLATE DATABASE_DEFAULT;

            UPDATE #nomor
            SET kode_ref = CONCAT(satuan_code, '-',
                                  CASE WHEN no_urut > 999
                                       THEN CAST(no_urut AS VARCHAR(10))
                                       ELSE RIGHT(CONCAT('000', no_urut), 3) END);

            -- qr_token: 10 karakter acak [A-Za-z0-9]. NEWID() dievaluasi per baris,
            -- jadi pembuatan token tetap set-based.
            DECLARE @CS CHAR(62) = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

            UPDATE n
            SET qr_token =
                  SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 1,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 2,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 3,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 4,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 5,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 6,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 7,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 8,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 9,1)) % 62 + 1, 1)
                + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b,10,1)) % 62 + 1, 1)
            FROM #nomor n
            CROSS APPLY (SELECT CAST(NEWID() AS BINARY(16)) AS b) g;

            -- Ulangi untuk token yang bentrok: dengan token yang sudah ada
            -- (TERMASUK baris terhapus -- unique index qr_token tanpa filter) atau
            -- kembar di dalam batch ini sendiri.
            DECLARE @bentrok INT = 1, @putaran INT = 0;

            WHILE @bentrok > 0 AND @putaran < 20
            BEGIN
                SET @putaran += 1;

                UPDATE n
                SET qr_token =
                      SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 1,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 2,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 3,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 4,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 5,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 6,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 7,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 8,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b, 9,1)) % 62 + 1, 1)
                    + SUBSTRING(@CS, CONVERT(TINYINT, SUBSTRING(g.b,10,1)) % 62 + 1, 1)
                FROM #nomor n
                CROSS APPLY (SELECT CAST(NEWID() AS BINARY(16)) AS b) g
                WHERE EXISTS (SELECT 1 FROM tni.personel p WHERE p.qr_token = n.qr_token)
                   OR EXISTS (SELECT 1 FROM #nomor n2 WHERE n2.qr_token = n.qr_token
                                                        AND n2.staging_id < n.staging_id);

                SELECT @bentrok = COUNT(*)
                FROM #nomor n
                WHERE EXISTS (SELECT 1 FROM tni.personel p WHERE p.qr_token = n.qr_token)
                   OR EXISTS (SELECT 1 FROM #nomor n2 WHERE n2.qr_token = n.qr_token
                                                        AND n2.staging_id < n.staging_id);
            END

            IF @bentrok > 0
            BEGIN
                RAISERROR('Gagal membuat qr_token unik setelah 20 putaran.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END

            INSERT INTO tni.personel
                (order_id, satuan_id, kode_ref, no_urut, qr_token,
                 pangkat, nama, nrp, no_hp, gender, tinggi_badan, berat_badan, kategori,
                 pola_kemeja_id, pola_celana_id, size_baju_isian, size_celana_isian,
                 email_pengisi, submitted_at,
                 lingkar_leher, lebar_bahu, lingkar_dada, lingkar_perut,
                 panjang_badan_depan, panjang_lengan, lingkar_lengan, lingkar_ketiak,
                 lingkar_pinggang_celana, lingkar_pinggul, lingkar_pesak, lingkar_paha,
                 lingkar_lutut, lingkar_celana_bawah, panjang_celana,
                 status_data, catatan_review, created_by)
            SELECT @OrderId, c.satuan_id, n.kode_ref, n.no_urut, n.qr_token,
                   c.pangkat, c.nama, c.nrp, c.noHp, c.gender, c.tinggiBadan, c.beratBadan, c.kategori,
                   c.pola_kemeja_id, c.pola_celana_id, c.sizeBajuIsian, c.sizeCelanaIsian,
                   c.emailPengisi, c.submittedAt,
                   c.lingkarLeher, c.lebarBahu, c.lingkarDada, c.lingkarPerut,
                   c.panjangBadanDepan, c.panjangLengan, c.lingkarLengan, c.lingkarKetiak,
                   c.lingkarPinggangCelana, c.lingkarPinggul, c.lingkarPesak, c.lingkarPaha,
                   c.lingkarLutut, c.lingkarCelanaBawah, c.panjangCelana,
                   CASE WHEN c.hasil_validasi = 'REVIEW' THEN 'PERLU_REVIEW' ELSE 'OK' END,
                   CASE WHEN c.hasil_validasi = 'REVIEW' THEN c.pesan_error ELSE NULL END,
                   @UserId
            FROM #c c
            JOIN #nomor n ON n.staging_id = c.staging_id
            ORDER BY n.satuan_id, n.no_urut;

            SET @Baru = @@ROWCOUNT;

            -- catat personel_id baru ke staging
            UPDATE st
            SET personel_id = p.personel_id
            FROM tni.import_staging st
            JOIN #nomor n ON n.staging_id = st.staging_id
            JOIN tni.personel p ON p.order_id = @OrderId AND p.kode_ref = n.kode_ref
                                AND p.deleted_at IS NULL
            WHERE st.batch_id = @BatchId;
        END

        -- personel_id untuk baris PERBARUI
        UPDATE st
        SET personel_id = c.existing_id
        FROM tni.import_staging st
        JOIN #c c ON c.staging_id = st.staging_id
        WHERE st.batch_id = @BatchId AND c.aksi = 'PERBARUI';

        UPDATE tni.import_batch
        SET committed_at = SYSDATETIME(),
            committed_by = @UserId,
            updated_at   = SYSDATETIME(),
            updated_by   = @UserId
        WHERE batch_id = @BatchId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @Baru AS JumlahBaru, @Perbarui AS JumlahDiperbarui;
END;
GO
