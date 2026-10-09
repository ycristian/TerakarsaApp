-- Prompt 70 -- Semua procedure yang dipanggil aplikasi gate (TerakarsaApp.GateApp lewat
-- GateController, header X-Gate-Api-Key). Seluruh keputusan masuk/pulang ada DI SINI, bukan di
-- aplikasi gate: GateApp hanya mengantre tap dan menampilkan hasil.
--
-- Aturan jam yang dipegang semua procedure di file ini:
--   * check_in_at / check_out_at SELALU dari @TappedAt (waktu tap asli yang dikirim gate).
--     Inilah yang membuat antrian offline tetap tercatat di jam yang benar.
--   * SYSDATETIME() HANYA untuk kolom audit (created_at/updated_at) dan untuk server_time.
--
-- created_by semua mutasi dari gate = user sistem 'gate_system' (@UserId, dibaca API dari
-- appsettings Gate:SystemUserId). Pelaku sebenarnya (satpam) ada di kolom *_by_employee_id.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- Jam masuk (start_time) satu divisi pada satu tanggal.
-- Urutan sumber:
--   1. work_schedule_defaults divisi itu untuk hari tsb, is_working_day = 1
--   2. kalau tidak ada / hari itu libur: baris HARI KERJA TERDEKAT milik divisi yang sama
--      (jarak hari melingkar 1=Senin..7=Minggu; seri -> hari yang lebih awal)
--   3. kalau divisi itu sama sekali tidak punya baris hari kerja: KONSTANTA 08:00.
--      Fallback terakhir ini disengaja -- jendela check-in tidak boleh hilang hanya karena
--      jadwal divisi belum diisi admin, kalau tidak tap pagi akan salah dibaca jadi check out.
-- ============================================================================
CREATE OR ALTER FUNCTION dbo.SIS_fn_GateShiftStart(@DivisionId INT, @AtDate DATE)
RETURNS TIME(0)
AS
BEGIN
    -- Konversi DATEPART(WEEKDAY) menjadi 1 = Senin ... 7 = Minggu, tahan berapa pun nilai
    -- @@DATEFIRST sesi (pola sama dengan sp_DailyPlan_Select.sql).
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @AtDate) + @@DATEFIRST - 2) % 7) + 1;
    DECLARE @StartTime TIME(0);

    SELECT @StartTime = wsd.start_time
    FROM work_schedule_defaults wsd
    WHERE wsd.division_id = @DivisionId
      AND wsd.day_of_week = @Dow
      AND wsd.is_working_day = 1
      AND wsd.deleted_at IS NULL;

    IF @StartTime IS NULL
    BEGIN
        SELECT TOP 1 @StartTime = wsd.start_time
        FROM work_schedule_defaults wsd
        WHERE wsd.division_id = @DivisionId
          AND wsd.is_working_day = 1
          AND wsd.deleted_at IS NULL
        ORDER BY
            -- jarak melingkar antara hari jadwal dan hari tap (0..3)
            CASE WHEN ABS(wsd.day_of_week - @Dow) > 3 THEN 7 - ABS(wsd.day_of_week - @Dow)
                 ELSE ABS(wsd.day_of_week - @Dow) END ASC,
            wsd.day_of_week ASC;
    END

    RETURN ISNULL(@StartTime, '08:00:00');
END;
GO

-- ============================================================================
-- SIS_Gate_CardSync -- satu panggilan, tiga result set. Dipanggil CardSyncService tiap
-- CardSyncSeconds. Isi result set 1 & 2 menimpa penuh cache SQLite GateApp (cache murni,
-- tidak pernah jadi sumber kebenaran).
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_CardSync
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    -- (1) Semua kartu AKTIF + data tampilan layar gate.
    SELECT ec.card_uid                          AS CardUid,
           ec.card_type                         AS CardType,
           e.employee_id                        AS EmployeeId,
           e.employee_name                      AS EmployeeName,
           e.employee_code                      AS EmployeeCode,
           p.position_name                      AS PositionName,
           p.is_gate_operator                   AS IsGateOperator,
           e.division_id                        AS DivisionId,
           d.division_name                      AS DivisionName,
           r.resource_name                      AS ResourceName,
           r.color_hex                          AS ColorHex,
           dbo.SIS_fn_GateShiftStart(e.division_id, @Today) AS StartTime
    FROM employee_cards ec
    INNER JOIN employees e ON e.employee_id = ec.employee_id AND e.deleted_at IS NULL
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    WHERE ec.deleted_at IS NULL
      AND ec.card_status = 'AKTIF'
    ORDER BY ec.card_uid ASC;

    -- (2) Semua karyawan aktif -- daftar pilih saat mendaftarkan kartu & mengubah data.
    SELECT e.employee_id      AS EmployeeId,
           e.employee_name    AS EmployeeName,
           e.employee_code    AS EmployeeCode,
           e.phone_no         AS Phone,
           e.division_id      AS DivisionId,
           d.division_name    AS DivisionName,
           p.position_name    AS PositionName,
           e.resource_id      AS ResourceId,
           r.resource_name    AS ResourceName,
           r.color_hex        AS ColorHex,
           CAST(CASE WHEN EXISTS (
                SELECT 1 FROM employee_cards ec
                WHERE ec.employee_id = e.employee_id
                  AND ec.card_status = 'AKTIF' AND ec.deleted_at IS NULL
           ) THEN 1 ELSE 0 END AS BIT) AS HasActiveCard
    FROM employees e
    INNER JOIN divisions d ON d.division_id = e.division_id
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    WHERE e.deleted_at IS NULL AND e.is_active = 1
    ORDER BY d.division_name ASC, r.resource_name ASC, e.employee_name ASC;

    -- (3) Satu baris: jam server (untuk deteksi selisih jam tablet) + jumlah karyawan aktif.
    SELECT SYSDATETIME() AS ServerTime,
           (SELECT COUNT(*) FROM employees WHERE deleted_at IS NULL AND is_active = 1) AS ActiveEmployeeCount;
END;
GO

-- ============================================================================
-- Satu-satunya tempat bentuk result set SIS_Gate_Tap dirakit, supaya jalur idempoten dan
-- jalur normal mengembalikan kolom yang persis sama. @AtTime = @TappedAt, dipakai menghitung
-- durasi sesi yang masih OPEN (layar PERLU_KONFIRMASI).
-- Didefinisikan SEBELUM SIS_Gate_Tap supaya script bersih tanpa peringatan dependensi
-- saat dijalankan di database yang masih kosong.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_TapResult
    @ResultCode  VARCHAR(30),
    @SessionId   INT = NULL,
    @EmployeeId  INT = NULL,
    @CardUid     VARCHAR(20) = NULL,
    @AtTime      DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @ResultCode                      AS ResultCode,
           e.employee_name                  AS EmployeeName,
           e.employee_code                  AS EmployeeCode,
           p.position_name                  AS PositionName,
           r.resource_name                  AS ResourceName,
           r.color_hex                      AS ColorHex,
           s.check_in_at                    AS CheckInAt,
           s.check_out_at                   AS CheckOutAt,
           CASE WHEN s.attendance_session_id IS NULL THEN NULL
                WHEN s.check_out_at IS NOT NULL THEN DATEDIFF(MINUTE, s.check_in_at, s.check_out_at)
                ELSE DATEDIFF(MINUTE, s.check_in_at, ISNULL(@AtTime, SYSDATETIME())) END AS DurationMinutes,
           @CardUid                         AS CardUid,
           -- CHECK_OUT dengan check_out_at NULL = sesi ditutup sebagai ANOMALI (satpam memilih
           -- "kartu lupa dikembalikan"): kartunya diterima, tapi jam pulangnya memang tidak
           -- diketahui, jadi pesannya tidak boleh berbunyi "pulang tercatat".
           CAST(CASE
                WHEN @ResultCode = 'CHECK_OUT' AND s.check_out_at IS NULL
                     THEN 'Kartu diterima. Sesi ditandai perlu koreksi.'
                WHEN @ResultCode = 'CHECK_IN'            THEN 'Masuk tercatat.'
                WHEN @ResultCode = 'CHECK_OUT'           THEN 'Pulang tercatat.'
                WHEN @ResultCode = 'PERLU_KONFIRMASI'    THEN 'Sesi lebih dari 14 jam -- pilih yang benar.'
                WHEN @ResultCode = 'DUPLIKAT'            THEN 'Sudah tercatat.'
                WHEN @ResultCode = 'KARTU_NONAKTIF'      THEN 'Kartu sudah nonaktif. Lapor ke petugas untuk kartu pengganti.'
                WHEN @ResultCode = 'KARTU_TIDAK_DIKENAL' THEN 'Kartu tidak dikenal. Lapor ke petugas untuk didaftarkan sebagai kartu pengganti.'
                ELSE 'Tap tidak dapat diproses.' END AS VARCHAR(200)) AS Message
    -- Baris tunggal dijamin ada walau @EmployeeId/@SessionId NULL (kartu tidak dikenal).
    FROM (SELECT 1 AS one) anchor
    LEFT JOIN employees e ON e.employee_id = @EmployeeId
    LEFT JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    LEFT JOIN attendance_sessions s ON s.attendance_session_id = @SessionId;
END;
GO

-- ============================================================================
-- SIS_Gate_Tap -- inti logika sesi (pasal 2 prompt 70).
--
-- | Kondisi tap                                            | Hasil                          |
-- |--------------------------------------------------------|--------------------------------|
-- | di dalam jendela, sudah ada sesi OPEN dari jendela ini  | DUPLIKAT, jam masuk = TERENDAH |
-- | di dalam jendela check-in (start_time - 2j .. start)    | SELALU CHECK IN (hari baru)    |
-- | di luar jendela, tidak ada sesi OPEN, sesi terakhir     | CHECK OUT ulang, jam pulang =  |
-- |   CLOSED dan check in s/d tap <= 14 jam                 |   TERTINGGI (sesi yang sama)   |
-- | di luar jendela, tidak ada sesi OPEN                    | CHECK IN                       |
-- | di luar jendela, sesi OPEN <= 14 jam                    | CHECK OUT normal               |
-- | di luar jendela, sesi OPEN > 14 jam dan <= 24 jam       | PERLU_KONFIRMASI (satpam pilih)|
-- | di luar jendela, sesi OPEN > 24 jam                     | tutup paksa ANOMALI            |
--
-- PENYIMPANGAN YANG DISENGAJA pada baris terakhir: prompt hanya menyebut "tutup paksa sebagai
-- ANOMALI, tanpa pilihan" dan tidak menyediakan result_code untuk "sesi ditutup tapi tidak ada
-- yang dibuka". Di sini sesi basi itu ditutup ANOMALI lalu tap-nya diperlakukan sebagai CHECK
-- IN sesi baru -- persis seperti aturan "check in saat ada sesi OPEN" di dalam jendela. Dengan
-- begitu invarian "setiap tap valid membuka ATAU menutup satu sesi" tetap berlaku dan tap tidak
-- pernah gagal; sesi basinya masuk antrian halaman Koreksi.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_Tap
    @TapUid          UNIQUEIDENTIFIER,
    @CardUid         VARCHAR(20),
    @TappedAt        DATETIME2,
    @GateCode        VARCHAR(30),
    @ConfirmAction   VARCHAR(20) = NULL,    -- NULL / 'LEMBUR' / 'LUPA_KEMBALI'
    @IsOfflineReplay BIT = 0,
    @UserId          INT = NULL             -- user sistem gate_system
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ResultCode   VARCHAR(30) = NULL,
            @SessionId    INT = NULL,
            @EmployeeId   INT = NULL,
            @Uid          VARCHAR(20) = NULL;

    -- ---------- Normalisasi UID ----------
    -- Reader mengeluarkan 10 digit desimal, tapi nol di depan bisa hilang di perjalanan.
    DECLARE @Raw VARCHAR(20) = LTRIM(RTRIM(ISNULL(@CardUid, '')));
    IF @Raw = '' OR PATINDEX('%[^0-9]%', @Raw) > 0 OR LEN(@Raw) > 10
    BEGIN
        -- UID tidak berbentuk angka 10 digit: tetap dijawab sebagai kartu tidak dikenal,
        -- TANPA dicatat (bukan percobaan tap kartu, tapi input rusak).
        SELECT 'KARTU_TIDAK_DIKENAL' AS ResultCode,
               CAST(NULL AS VARCHAR(150)) AS EmployeeName, CAST(NULL AS VARCHAR(30)) AS EmployeeCode,
               CAST(NULL AS VARCHAR(150)) AS PositionName, CAST(NULL AS VARCHAR(150)) AS ResourceName,
               CAST(NULL AS VARCHAR(7)) AS ColorHex,
               CAST(NULL AS DATETIME2) AS CheckInAt, CAST(NULL AS DATETIME2) AS CheckOutAt,
               CAST(NULL AS INT) AS DurationMinutes,
               CAST(@Raw AS VARCHAR(20)) AS CardUid,
               CAST('Pembacaan kartu tidak sah.' AS VARCHAR(200)) AS Message;
        RETURN;
    END
    SET @Uid = RIGHT('0000000000' + @Raw, 10);

    -- ---------- Idempoten: @TapUid yang sudah pernah diproses ----------
    -- Melindungi dari jaringan yang putus SETELAH server commit tapi SEBELUM GateApp menerima
    -- balasan -- GateApp mengirim ulang baris antrian yang sama, hasilnya harus identik.
    SELECT @ResultCode = gt.result_code,
           @SessionId  = gt.attendance_session_id,
           @EmployeeId = gt.employee_id
    FROM gate_taps gt
    WHERE gt.tap_uid = @TapUid;

    IF @ResultCode IS NOT NULL
    BEGIN
        EXEC SIS_Gate_TapResult @ResultCode = @ResultCode, @SessionId = @SessionId,
                                @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
        RETURN;
    END

    -- ---------- Kartu ----------
    DECLARE @CardStatus VARCHAR(20) = NULL;

    SELECT TOP 1 @EmployeeId = ec.employee_id, @CardStatus = ec.card_status
    FROM employee_cards ec
    INNER JOIN employees e ON e.employee_id = ec.employee_id AND e.deleted_at IS NULL
    WHERE ec.card_uid = @Uid AND ec.deleted_at IS NULL
    ORDER BY CASE WHEN ec.card_status = 'AKTIF' THEN 0 ELSE 1 END ASC, ec.issued_at DESC;

    IF @EmployeeId IS NULL OR @CardStatus <> 'AKTIF'
    BEGIN
        -- Kartu tidak dikenal / nonaktif TETAP dicatat -- ini bukti percobaan tap, dan UID-nya
        -- yang tampil di layar merah dipakai satpam untuk mendaftarkan kartu pengganti.
        SET @ResultCode = CASE WHEN @EmployeeId IS NULL THEN 'KARTU_TIDAK_DIKENAL' ELSE 'KARTU_NONAKTIF' END;

        INSERT INTO gate_taps (tap_uid, card_uid, tapped_at, gate_code, result_code,
                               attendance_session_id, employee_id, is_offline_replay, created_at)
        VALUES (@TapUid, @Uid, @TappedAt, @GateCode, @ResultCode,
                NULL, CASE WHEN @CardStatus = 'NONAKTIF' THEN @EmployeeId ELSE NULL END,
                @IsOfflineReplay, SYSDATETIME());

        EXEC SIS_Gate_TapResult @ResultCode = @ResultCode, @SessionId = NULL,
                                @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
        RETURN;
    END

    -- ---------- Cooldown 30 detik ----------
    -- Dicek per card_uid (bukan per karyawan): kartu yang sama disentuh dua kali karena reader
    -- membaca ganda. Baris DUPLIKAT sendiri dikecualikan supaya rentetan tap tetap diukur dari
    -- tap sungguhan yang pertama.
    IF EXISTS (
        SELECT 1 FROM gate_taps gt
        WHERE gt.card_uid = @Uid
          AND gt.result_code NOT IN ('DUPLIKAT', 'KARTU_TIDAK_DIKENAL', 'KARTU_NONAKTIF')
          AND gt.tapped_at <= @TappedAt
          AND gt.tapped_at > DATEADD(SECOND, -30, @TappedAt)
    )
    BEGIN
        -- TOP 1 WAJIB: SELECT penugasan variabel tanpa TOP akan menyisakan nilai baris
        -- TERAKHIR yang diproses, bukan baris pertama menurut ORDER BY.
        SELECT TOP 1 @SessionId = s.attendance_session_id
        FROM attendance_sessions s
        WHERE s.employee_id = @EmployeeId AND s.deleted_at IS NULL
        ORDER BY s.check_in_at DESC;

        INSERT INTO gate_taps (tap_uid, card_uid, tapped_at, gate_code, result_code,
                               attendance_session_id, employee_id, is_offline_replay, created_at)
        VALUES (@TapUid, @Uid, @TappedAt, @GateCode, 'DUPLIKAT', @SessionId, @EmployeeId,
                @IsOfflineReplay, SYSDATETIME());

        EXEC SIS_Gate_TapResult @ResultCode = 'DUPLIKAT', @SessionId = @SessionId,
                                @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
        RETURN;
    END

    -- ---------- Jendela check-in ----------
    DECLARE @DivisionId INT, @ResourceId INT;
    SELECT @DivisionId = e.division_id, @ResourceId = e.resource_id
    FROM employees e WHERE e.employee_id = @EmployeeId;

    DECLARE @TapDate DATE = CAST(@TappedAt AS DATE);
    DECLARE @StartTime TIME(0) = dbo.SIS_fn_GateShiftStart(@DivisionId, @TapDate);
    DECLARE @WindowEnd DATETIME2 = DATEADD(SECOND, DATEDIFF(SECOND, '00:00:00', @StartTime), CAST(@TapDate AS DATETIME2));
    -- Jendela = start_time - 2 jam s/d start_time. Kalau start_time < 02:00, batas bawah
    -- dipotong ke 00:00 tanggal yang sama -- sengaja tidak melintasi tengah malam supaya tap
    -- jam 23:xx tidak diperlakukan sebagai check in hari berikutnya.
    DECLARE @WindowStart DATETIME2 = CASE
        WHEN DATEDIFF(SECOND, '00:00:00', @StartTime) < 7200 THEN CAST(@TapDate AS DATETIME2)
        ELSE DATEADD(HOUR, -2, @WindowEnd) END;
    DECLARE @InWindow BIT = CASE WHEN @TappedAt >= @WindowStart AND @TappedAt <= @WindowEnd THEN 1 ELSE 0 END;

    -- ---------- Sesi OPEN yang sedang berjalan ----------
    DECLARE @OpenSessionId INT = NULL, @OpenCheckInAt DATETIME2 = NULL;
    SELECT @OpenSessionId = s.attendance_session_id, @OpenCheckInAt = s.check_in_at
    FROM attendance_sessions s
    WHERE s.employee_id = @EmployeeId AND s.session_status = 'OPEN' AND s.deleted_at IS NULL;

    DECLARE @OpenMinutes INT = CASE WHEN @OpenSessionId IS NULL THEN NULL
                                    ELSE DATEDIFF(MINUTE, @OpenCheckInAt, @TappedAt) END;

    -- ---------- MASUK setelah MASUK -> jam masuk TERENDAH ----------
    -- Tap di dalam jendela check-in padahal sudah ada sesi OPEN yang check in-nya di jendela
    -- yang SAMA: orangnya tap dua kali pagi ini. Bukan hari baru -- sesi pagi tetap dipakai
    -- (TIDAK ditutup ANOMALI) dan jam masuknya jam yang paling awal. MIN dipakai karena replay
    -- offline bisa datang tidak berurutan. Sesi OPEN kemarin tidak memenuhi syarat ini, jadi
    -- tetap tersapu ANOMALI seperti biasa di bawah.
    IF @InWindow = 1 AND @OpenSessionId IS NOT NULL
       AND @OpenCheckInAt >= @WindowStart AND @OpenCheckInAt <= @WindowEnd
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            IF @TappedAt < @OpenCheckInAt
                UPDATE attendance_sessions
                SET check_in_at = @TappedAt,
                    updated_at  = SYSDATETIME(),
                    updated_by  = @UserId
                WHERE attendance_session_id = @OpenSessionId;

            INSERT INTO gate_taps (tap_uid, card_uid, tapped_at, gate_code, result_code,
                                   attendance_session_id, employee_id, is_offline_replay, created_at)
            VALUES (@TapUid, @Uid, @TappedAt, @GateCode, 'DUPLIKAT', @OpenSessionId, @EmployeeId,
                    @IsOfflineReplay, SYSDATETIME());

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        EXEC SIS_Gate_TapResult @ResultCode = 'DUPLIKAT', @SessionId = @OpenSessionId,
                                @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
        RETURN;
    END

    -- ---------- PULANG setelah PULANG -> jam pulang TERTINGGI ----------
    -- Di luar jendela, tidak ada sesi OPEN, dan sesi TERAKHIR orang ini CLOSED (jam pulang
    -- diketahui) dengan rentang check in s/d tap ini masih <= 14 jam: tap ini pulang ulang
    -- (mis. keluar istirahat lalu keluar lagi sore), BUKAN check in baru. Sesi yang sama
    -- diperpanjang; jam pulang = yang paling akhir (MAX, tahan replay offline tidak berurutan).
    -- Sesi ANOMALI (jam pulang tidak diketahui) sengaja tidak ikut -- itu urusan Koreksi.
    IF @InWindow = 0 AND @OpenSessionId IS NULL
    BEGIN
        DECLARE @LastSessionId INT = NULL, @LastCheckInAt DATETIME2 = NULL,
                @LastCheckOutAt DATETIME2 = NULL, @LastStatus VARCHAR(20) = NULL;

        SELECT TOP 1 @LastSessionId  = s.attendance_session_id,
                     @LastCheckInAt  = s.check_in_at,
                     @LastCheckOutAt = s.check_out_at,
                     @LastStatus     = s.session_status
        FROM attendance_sessions s
        WHERE s.employee_id = @EmployeeId AND s.deleted_at IS NULL
        ORDER BY s.check_in_at DESC;

        IF @LastStatus = 'CLOSED' AND @LastCheckOutAt IS NOT NULL
           AND @TappedAt >= @LastCheckInAt
           AND DATEDIFF(MINUTE, @LastCheckInAt, @TappedAt) <= 840
        BEGIN
            BEGIN TRY
                BEGIN TRANSACTION;

                IF @TappedAt > @LastCheckOutAt
                    UPDATE attendance_sessions
                    SET check_out_at = @TappedAt,
                        updated_at   = SYSDATETIME(),
                        updated_by   = @UserId
                    WHERE attendance_session_id = @LastSessionId;

                INSERT INTO gate_taps (tap_uid, card_uid, tapped_at, gate_code, result_code,
                                       attendance_session_id, employee_id, is_offline_replay, created_at)
                VALUES (@TapUid, @Uid, @TappedAt, @GateCode, 'CHECK_OUT', @LastSessionId, @EmployeeId,
                        @IsOfflineReplay, SYSDATETIME());

                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
                THROW;
            END CATCH

            EXEC SIS_Gate_TapResult @ResultCode = 'CHECK_OUT', @SessionId = @LastSessionId,
                                    @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
            RETURN;
        END
    END

    -- PERLU_KONFIRMASI: SP tidak mengubah APA PUN dan tidak mencatat tap -- hanya mengembalikan
    -- info sesi. Gate menampilkan layar pilihan lalu memanggil ulang dengan @ConfirmAction.
    -- Saat offline layar konfirmasi tidak mungkin muncul (butuh server), jadi replay offline
    -- langsung diperlakukan sebagai LUPA_KEMBALI -> ANOMALI, dikoreksi admin belakangan.
    IF @InWindow = 0 AND @OpenSessionId IS NOT NULL
       AND @OpenMinutes > 840 AND @OpenMinutes <= 1440
       AND @ConfirmAction IS NULL AND @IsOfflineReplay = 0
    BEGIN
        EXEC SIS_Gate_TapResult @ResultCode = 'PERLU_KONFIRMASI', @SessionId = @OpenSessionId,
                                @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- CHECK OUT normal: di luar jendela, sesi OPEN <= 14 jam, ATAU satpam memilih LEMBUR.
        IF @InWindow = 0 AND @OpenSessionId IS NOT NULL
           AND (@OpenMinutes <= 840 OR (@OpenMinutes <= 1440 AND @ConfirmAction = 'LEMBUR'))
        BEGIN
            UPDATE attendance_sessions
            SET check_out_at   = @TappedAt,
                session_status = 'CLOSED',
                -- LEMBUR_DIKONFIRMASI = sesi panjang yang sudah dibenarkan satpam; sengaja
                -- TIDAK masuk laporan anomali.
                session_flag   = CASE WHEN @ConfirmAction = 'LEMBUR' THEN 'LEMBUR_DIKONFIRMASI' ELSE session_flag END,
                updated_at     = SYSDATETIME(),
                updated_by     = @UserId
            WHERE attendance_session_id = @OpenSessionId;

            SET @ResultCode = 'CHECK_OUT';
            SET @SessionId = @OpenSessionId;
        END
        ELSE
        BEGIN
            -- Semua jalur lain berakhir sebagai CHECK IN. Sesi OPEN yang masih menggantung
            -- ditutup paksa dulu supaya tap pagi TIDAK PERNAH gagal karena sesi kemarin:
            --   * LUPA_KEMBALI = pilihan eksplisit satpam (sesi 14-24 jam)
            --   * BELUM_CHECKOUT = sesi menggantung yang tersapu tap baru (termasuk sesi
            --     > 24 jam dan sesi panjang yang masuk lewat replay offline -- saat offline
            --     layar konfirmasi tidak mungkin muncul, jadi tidak ada pilihan satpam)
            -- check_out_at WAJIB NULL untuk ANOMALI -- jamnya tidak diketahui, bukan ditebak.
            IF @OpenSessionId IS NOT NULL
            BEGIN
                UPDATE attendance_sessions
                SET session_status = 'ANOMALI',
                    check_out_at   = NULL,
                    session_flag   = CASE WHEN @ConfirmAction = 'LUPA_KEMBALI'
                                          THEN 'LUPA_KEMBALI' ELSE 'BELUM_CHECKOUT' END,
                    updated_at     = SYSDATETIME(),
                    updated_by     = @UserId
                WHERE attendance_session_id = @OpenSessionId;
            END

            -- Satpam memilih LUPA_KEMBALI: sesi lama ditutup ANOMALI dan TIDAK ada sesi baru
            -- (orangnya memang tidak sedang masuk, cuma mengembalikan kartu).
            IF @ConfirmAction = 'LUPA_KEMBALI' AND @OpenSessionId IS NOT NULL AND @InWindow = 0
            BEGIN
                SET @ResultCode = 'CHECK_OUT';
                SET @SessionId = @OpenSessionId;
            END
            ELSE
            BEGIN
                -- division_id/resource_id di-SNAPSHOT di sini supaya mutasi line nanti tidak
                -- mengubah riwayat absensi.
                INSERT INTO attendance_sessions
                    (employee_id, division_id, resource_id, work_date, check_in_at, check_out_at,
                     session_status, session_flag, entry_source, created_at, created_by)
                VALUES
                    (@EmployeeId, @DivisionId, @ResourceId, @TapDate, @TappedAt, NULL,
                     'OPEN', NULL, 'GATE', SYSDATETIME(), @UserId);

                SET @SessionId = CAST(SCOPE_IDENTITY() AS INT);
                SET @ResultCode = 'CHECK_IN';
            END
        END

        INSERT INTO gate_taps (tap_uid, card_uid, tapped_at, gate_code, result_code,
                               attendance_session_id, employee_id, is_offline_replay, created_at)
        VALUES (@TapUid, @Uid, @TappedAt, @GateCode, @ResultCode, @SessionId, @EmployeeId,
                @IsOfflineReplay, SYSDATETIME());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC SIS_Gate_TapResult @ResultCode = @ResultCode, @SessionId = @SessionId,
                            @EmployeeId = @EmployeeId, @CardUid = @Uid, @AtTime = @TappedAt;
END;
GO
-- ============================================================================
-- SIS_Gate_Counts -- tiga angka untuk layar tunggu.
-- @GateCode diterima supaya tanda tangan endpoint stabil; sengaja TIDAK dipakai memfilter --
-- sesi absensi milik karyawan, bukan milik gate tertentu (satu pabrik bisa punya beberapa
-- gate dan orang yang sama boleh masuk lewat gate mana pun).
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_Counts
    @GateCode VARCHAR(30) = NULL,
    @AtDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @AtDate = ISNULL(@AtDate, CAST(SYSDATETIME() AS DATE));

    SELECT
        -- Hadir = kartu sedang diambil (orang ada di dalam), apa pun tanggal check in-nya.
        (SELECT COUNT(*) FROM attendance_sessions s
         WHERE s.session_status = 'OPEN' AND s.deleted_at IS NULL) AS PresentCount,
        -- Belum ambil kartu = karyawan aktif tanpa sesi OPEN.
        (SELECT COUNT(*) FROM employees e
         WHERE e.deleted_at IS NULL AND e.is_active = 1
           AND NOT EXISTS (SELECT 1 FROM attendance_sessions s
                           WHERE s.employee_id = e.employee_id
                             AND s.session_status = 'OPEN' AND s.deleted_at IS NULL)) AS NotTakenCount,
        -- Perlu cek = sesi ANOMALI hari ini yang belum diberi tanda sudah diperiksa admin.
        (SELECT COUNT(*) FROM attendance_sessions s
         WHERE s.session_status = 'ANOMALI' AND s.deleted_at IS NULL
           AND s.work_date = @AtDate
           AND ISNULL(s.session_flag, '') <> 'DIVERIFIKASI') AS NeedCheckCount;
END;
GO

-- ============================================================================
-- SIS_Gate_Pending -- daftar untuk menu satpam.
--   BELUM_AMBIL        -> karyawan aktif tanpa sesi OPEN
--   BELUM_KEMBALI      -> sesi OPEN
--   BELUM_PUNYA_KARTU  -> karyawan aktif tanpa satu pun kartu AKTIF
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_Pending
    @Mode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Mode = 'BELUM_KEMBALI'
    BEGIN
        SELECT e.employee_id   AS EmployeeId,
               e.employee_name AS EmployeeName,
               e.employee_code AS EmployeeCode,
               d.division_name AS DivisionName,
               r.resource_name AS ResourceName,
               r.color_hex     AS ColorHex,
               s.check_in_at   AS CheckInAt,
               -- Dipakai tombol "Batalkan" di menu satpam (SIS_Gate_CancelSession).
               s.attendance_session_id AS SessionId
        FROM attendance_sessions s
        INNER JOIN employees e ON e.employee_id = s.employee_id
        INNER JOIN divisions d ON d.division_id = s.division_id
        LEFT JOIN resources r ON r.resource_id = s.resource_id AND r.deleted_at IS NULL
        WHERE s.session_status = 'OPEN' AND s.deleted_at IS NULL
        ORDER BY s.check_in_at ASC;
        RETURN;
    END

    IF @Mode NOT IN ('BELUM_AMBIL', 'BELUM_PUNYA_KARTU')
    BEGIN
        RAISERROR('Mode daftar tidak dikenal.', 16, 1);
        RETURN;
    END

    SELECT e.employee_id   AS EmployeeId,
           e.employee_name AS EmployeeName,
           e.employee_code AS EmployeeCode,
           d.division_name AS DivisionName,
           r.resource_name AS ResourceName,
           r.color_hex     AS ColorHex,
           CAST(NULL AS DATETIME2) AS CheckInAt,
           -- Kolom wajib ada di setiap mode: API membaca ketiganya ke DTO yang sama.
           CAST(NULL AS INT) AS SessionId
    FROM employees e
    INNER JOIN divisions d ON d.division_id = e.division_id
    LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
    WHERE e.deleted_at IS NULL AND e.is_active = 1
      AND (
            (@Mode = 'BELUM_AMBIL' AND NOT EXISTS (
                SELECT 1 FROM attendance_sessions s
                WHERE s.employee_id = e.employee_id AND s.session_status = 'OPEN' AND s.deleted_at IS NULL))
         OR (@Mode = 'BELUM_PUNYA_KARTU' AND NOT EXISTS (
                SELECT 1 FROM employee_cards ec
                WHERE ec.employee_id = e.employee_id AND ec.card_status = 'AKTIF' AND ec.deleted_at IS NULL))
          )
    -- Dikelompokkan per divisi lalu resource -- layar "Daftar kartu" memakai urutan ini apa
    -- adanya sebagai judul kelompok.
    ORDER BY d.division_name ASC, r.resource_name ASC, e.employee_name ASC;
END;
GO

-- ============================================================================
-- SIS_Gate_RegisterCard -- pendaftaran kartu dari perangkat gate oleh satpam.
-- Butuh ONLINE (tidak boleh diantrekan): UID kembar harus dicek ke server.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_RegisterCard
    @EmployeeId          INT,
    @CardUid             VARCHAR(20),
    @CardType            VARCHAR(20),       -- TETAP / SEMENTARA
    @DeactivateOldCards  BIT = 0,           -- 1 = kartu AKTIF milik karyawan ini di-NONAKTIF-kan dulu
    @OperatorEmployeeId  INT,               -- satpam
    @UserId              INT = NULL         -- user sistem gate_system
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Akses melekat pada JABATAN (positions.is_gate_operator), bukan pada kartu dan bukan pada
    -- user login -- aplikasi gate memang tanpa login.
    IF NOT EXISTS (
        SELECT 1 FROM employees e
        INNER JOIN positions p ON p.position_id = e.position_id
        WHERE e.employee_id = @OperatorEmployeeId AND e.deleted_at IS NULL AND e.is_active = 1
          AND p.deleted_at IS NULL AND p.is_gate_operator = 1
    )
    BEGIN
        RAISERROR('Jabatan petugas ini tidak berhak mendaftarkan kartu.', 16, 1);
        RETURN;
    END

    IF @CardType NOT IN ('TETAP', 'SEMENTARA')
    BEGIN
        RAISERROR('Jenis kartu harus TETAP atau SEMENTARA.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = @EmployeeId AND deleted_at IS NULL AND is_active = 1)
    BEGIN
        RAISERROR('Karyawan tidak ditemukan atau sudah nonaktif.', 16, 1);
        RETURN;
    END

    DECLARE @Uid VARCHAR(20);
    EXEC SIS_EmployeeCard_NormalizeUid @CardUid = @CardUid, @Normalized = @Uid OUTPUT;
    IF @Uid IS NULL RETURN;   -- helper sudah RAISERROR

    DECLARE @OwnerLabel VARCHAR(200) = NULL;
    EXEC SIS_EmployeeCard_GetUidOwner @CardUid = @Uid, @OwnerLabel = @OwnerLabel OUTPUT;
    IF @OwnerLabel IS NOT NULL
    BEGIN
        RAISERROR('Kartu %s sudah aktif untuk %s. Nonaktifkan kartu lamanya dulu.', 16, 1, @Uid, @OwnerLabel);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Satu karyawan BOLEH punya beberapa kartu AKTIF sekaligus (kartu tetap + sementara),
        -- jadi penonaktifan kartu lama hanya dilakukan kalau satpam memintanya.
        IF @DeactivateOldCards = 1
        BEGIN
            UPDATE employee_cards
            SET card_status = 'NONAKTIF',
                updated_at  = SYSDATETIME(),
                updated_by  = @UserId
            WHERE employee_id = @EmployeeId AND card_status = 'AKTIF' AND deleted_at IS NULL;
        END

        INSERT INTO employee_cards
            (employee_id, card_uid, card_type, card_status, issued_at, issued_by_employee_id, remarks, created_at, created_by)
        VALUES
            (@EmployeeId, @Uid, @CardType, 'AKTIF', SYSDATETIME(), @OperatorEmployeeId, NULL, SYSDATETIME(), @UserId);

        DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

        COMMIT TRANSACTION;

        SELECT @NewId AS NewId, @Uid AS CardUid;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- SIS_Gate_UpdateEmployee -- ubah data karyawan dari gate.
--
-- HANYA employee_name dan no. telp. resource_id / division_id / position_id TIDAK punya
-- parameter di sini DAN TIDAK BOLEH ditambahkan: resource menentukan siapa dibayar untuk hasil
-- produksi (Laporan Hanca), itu keputusan supervisor, bukan satpam.
--
-- No. telp disimpan ke employees.phone_no (kolom Prompt 58) dengan normalisasi yang sama:
-- buang semua non-digit, awalan 62 -> 0. Lihat catatan penyimpangan di alter_70_absensi_rfid.sql.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_UpdateEmployee
    @EmployeeId          INT,
    @EmployeeName        VARCHAR(150),
    @Phone               VARCHAR(30) = NULL,
    @OperatorEmployeeId  INT,
    @UserId              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1 FROM employees e
        INNER JOIN positions p ON p.position_id = e.position_id
        WHERE e.employee_id = @OperatorEmployeeId AND e.deleted_at IS NULL AND e.is_active = 1
          AND p.deleted_at IS NULL AND p.is_gate_operator = 1
    )
    BEGIN
        RAISERROR('Jabatan petugas ini tidak berhak mengubah data karyawan.', 16, 1);
        RETURN;
    END

    SET @EmployeeName = NULLIF(LTRIM(RTRIM(ISNULL(@EmployeeName, ''))), '');
    IF @EmployeeName IS NULL
    BEGIN
        RAISERROR('Nama karyawan wajib diisi.', 16, 1);
        RETURN;
    END

    -- Tolak, jangan diam-diam dibuang: "--" atau huruf dulu lolos jadi kosong dan MENGHAPUS
    -- nomor. Kosong/spasi saja tetap boleh (= hapus nomor yang salah ketik).
    IF PATINDEX('%[^0-9 +().-]%', ISNULL(@Phone, '')) > 0
    BEGIN
        RAISERROR('No. telp hanya boleh berisi angka.', 16, 1);
        RETURN;
    END

    DECLARE @Digits VARCHAR(30) = ISNULL(@Phone, '');
    WHILE PATINDEX('%[^0-9]%', @Digits) > 0
        SET @Digits = STUFF(@Digits, PATINDEX('%[^0-9]%', @Digits), 1, '');

    IF LTRIM(RTRIM(ISNULL(@Phone, ''))) <> '' AND @Digits = ''
    BEGIN
        RAISERROR('No. telp harus berisi angka.', 16, 1);
        RETURN;
    END

    IF LEFT(@Digits, 2) = '62'
        SET @Digits = '0' + SUBSTRING(@Digits, 3, LEN(@Digits));

    IF LEN(@Digits) > 0 AND LEN(@Digits) < 9
    BEGIN
        RAISERROR('No. telp minimal 9 digit.', 16, 1);
        RETURN;
    END

    DECLARE @PhoneNormalized VARCHAR(20) = NULLIF(LEFT(@Digits, 20), '');

    DECLARE @OldName VARCHAR(150), @OldPhone VARCHAR(20);
    SELECT @OldName = employee_name, @OldPhone = phone_no
    FROM employees WHERE employee_id = @EmployeeId AND deleted_at IS NULL;

    IF @OldName IS NULL
    BEGIN
        RAISERROR('Karyawan tidak ditemukan.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Berbeda dengan SIS_Employee_Manage (COALESCE, no. telp tidak bisa dikosongkan dari
        -- admin), di sini nilai dipakai apa adanya: satpam harus bisa menghapus nomor yang
        -- salah ketik.
        UPDATE employees
        SET employee_name = @EmployeeName,
            phone_no      = @PhoneNormalized,
            updated_at    = SYSDATETIME(),
            updated_by    = @UserId
        WHERE employee_id = @EmployeeId AND deleted_at IS NULL;

        -- Satu baris log per field yang BENAR-BENAR berubah. Tanpa ini, data karyawan bisa
        -- berubah dari gate tanpa jejak.
        IF ISNULL(@OldName, '') <> ISNULL(@EmployeeName, '')
            INSERT INTO employee_change_log (employee_id, field_name, old_value, new_value,
                                             changed_by_employee_id, source, created_at, created_by)
            VALUES (@EmployeeId, 'employee_name', @OldName, @EmployeeName,
                    @OperatorEmployeeId, 'GATE', SYSDATETIME(), @UserId);

        IF ISNULL(@OldPhone, '') <> ISNULL(@PhoneNormalized, '')
            INSERT INTO employee_change_log (employee_id, field_name, old_value, new_value,
                                             changed_by_employee_id, source, created_at, created_by)
            VALUES (@EmployeeId, 'phone_no', @OldPhone, @PhoneNormalized,
                    @OperatorEmployeeId, 'GATE', SYSDATETIME(), @UserId);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- SIS_Gate_CancelSession -- satpam membatalkan sesi OPEN dari menu gate (daftar "Belum
-- kembalikan kartu"), mis. karyawan salah ambil kartu orang lain.
-- Butuh ONLINE (tidak boleh diantrekan): pembatalan harus kena sesi yang SAAT INI masih
-- OPEN, bukan sesi yang mungkin sudah berubah ketika antrian terkirim.
-- Hanya sesi OPEN: sesi yang sudah CLOSED/ANOMALI sudah lewat dari gerbang dan koreksinya
-- milik admin (halaman Absensi -> Koreksi), bukan satpam.
-- Soft delete; satpam & alasan dicatat di remarks (aktor log tetap user gate_system).
-- gate_taps-nya sengaja TIDAK dihapus -- itu jejak tap fisik yang memang terjadi.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Gate_CancelSession
    @SessionId           INT,
    @Reason              VARCHAR(100),
    @OperatorEmployeeId  INT,               -- satpam
    @UserId              INT = NULL         -- user sistem gate_system
AS
BEGIN
    SET NOCOUNT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(ISNULL(@Reason, ''))), '');

    DECLARE @OperatorLabel VARCHAR(150) = NULL;
    SELECT @OperatorLabel = CONCAT(e.employee_name, CASE WHEN e.employee_code IS NULL THEN '' ELSE CONCAT(' (', e.employee_code, ')') END)
    FROM employees e
    INNER JOIN positions p ON p.position_id = e.position_id
    WHERE e.employee_id = @OperatorEmployeeId AND e.deleted_at IS NULL AND e.is_active = 1
      AND p.deleted_at IS NULL AND p.is_gate_operator = 1;

    IF @OperatorLabel IS NULL
    BEGIN
        RAISERROR('Jabatan petugas ini tidak berhak membatalkan absensi.', 16, 1);
        RETURN;
    END

    IF @Reason IS NULL
    BEGIN
        RAISERROR('Alasan pembatalan wajib dipilih.', 16, 1);
        RETURN;
    END

    UPDATE attendance_sessions
    SET remarks    = LEFT(CONCAT('Dibatalkan satpam ', @OperatorLabel, ': ', @Reason), 255),
        deleted_at = SYSDATETIME(),
        deleted_by = @UserId
    WHERE attendance_session_id = @SessionId
      AND session_status = 'OPEN'
      AND deleted_at IS NULL;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Sesi tidak ditemukan atau sudah tidak berjalan (sudah pulang / sudah dibatalkan). Muat ulang daftarnya.', 16, 1);
        RETURN;
    END
END;
GO
