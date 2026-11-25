/* =============================================================
   TMOS - Module CCTV - Seed 27 kamera EZVIZ pabrik AGS (dari mediamtx.yml)
   - name = mtx_path dulu (diedit belakangan di UI Master Kamera).
   - IP / serial / channel NVR = data inventaris saja.
   - User/password RTSP TIDAK disimpan (aturan schema cctv: hanya bicara ke MediaMTX).
   - Lewat cctv.SIS_Camera_Manage:
       path belum ada  -> CREATE
       path sudah ada  -> UPDATE, hanya mengisi ip/serial/channel/note yang masih kosong
                          (nama, area, urutan, tampil dibiarkan).
   Idempotent: aman dijalankan ulang.
   ============================================================= */

SET NOCOUNT ON;

DECLARE @UserId INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin');
IF @UserId IS NULL
BEGIN
    RAISERROR('User admin tidak ditemukan -- isi @UserId manual.', 16, 1);
    RETURN;
END

DECLARE @cam TABLE (
    seq int PRIMARY KEY, mtx_path nvarchar(50), serial_no nvarchar(30),
    nvr_channel int NULL, ip_address nvarchar(45), note nvarchar(200) NULL);

INSERT INTO @cam (seq, mtx_path, serial_no, nvr_channel, ip_address, note) VALUES
 ( 1, N'cam8_78', N'BH9487171',    1, N'192.168.10.107', N'IP statis dari NVR'),
 ( 2, N'cam8_86', N'BA5971997',    2, N'192.168.8.86',   NULL),
 ( 3, N'cam8_75', N'BA5971706',    3, N'192.168.10.65',  N'IP statis dari NVR'),
 ( 4, N'cam8_79', N'BA5843235',    4, N'192.168.10.109', N'IP statis dari NVR'),
 ( 5, N'cam8_73', N'BH9487363',    5, N'192.168.10.28',  N'IP statis dari NVR'),
 ( 6, N'cam8_66', N'BG2721214',    6, N'192.168.10.12',  N'IP statis dari NVR'),
 ( 7, N'cam8_69', N'BG2720816',    7, N'192.168.10.11',  N'IP statis dari NVR'),
 ( 8, N'cam8_76', N'BA5843428',    8, N'192.168.10.69',  N'IP statis dari NVR'),
 ( 9, N'cam8_67', N'BH9759444',    9, N'192.168.10.9',   N'IP statis dari NVR'),
 (10, N'cam8_72', N'BA5971707',   10, N'192.168.8.72',   NULL),
 (11, N'cam8_60', N'BG2720944',   11, N'192.168.10.10',  N'IP statis dari NVR'),
 (12, N'cam8_85', N'BH9400653',   12, N'192.168.10.103', N'IP statis dari NVR'),
 (13, N'cam8_61', N'BH9061319',   13, N'192.168.10.8',   N'IP statis dari NVR'),
 (14, N'cam8_65', N'BF8209338',   14, N'192.168.10.5',   N'IP statis dari NVR'),
 (15, N'cam8_74', N'BA5843300',   15, N'192.168.10.64',  N'IP statis dari NVR'),
 (16, N'cam8_62', N'BH9486868', NULL, N'192.168.8.62',   NULL),
 (17, N'cam8_63', N'BG2720965', NULL, N'192.168.8.63',   NULL),
 (18, N'cam8_64', N'BH9061614', NULL, N'192.168.8.64',   NULL),
 (19, N'cam8_68', N'BH9061601', NULL, N'192.168.8.68',   NULL),
 (20, N'cam8_71', N'BA5103356', NULL, N'192.168.8.71',   NULL),
 (21, N'cam8_77', N'BA5843099', NULL, N'192.168.8.77',   NULL),
 (22, N'cam8_80', N'BA5971798', NULL, N'192.168.8.80',   NULL),
 (23, N'cam8_81', N'BA5843266', NULL, N'192.168.8.81',   NULL),
 (24, N'cam8_82', N'BA5842554', NULL, N'192.168.10.112', N'IP statis dari NVR'),
 (25, N'cam8_83', N'BA4343011', NULL, N'192.168.8.83',   NULL),
 (26, N'cam8_84', N'BA4343376', NULL, N'192.168.8.84',   NULL),
 (27, N'cam8_47', N'BA5103566', NULL, N'192.168.8.47',   NULL);

DECLARE @seq int = 1, @max int = (SELECT MAX(seq) FROM @cam);
DECLARE @path nvarchar(50), @serial nvarchar(30), @nvr int, @ip nvarchar(45), @note nvarchar(200);
DECLARE @id int, @name nvarchar(100), @area nvarchar(50), @sort int, @vis bit;
DECLARE @eSerial nvarchar(30), @eNvr int, @eIp nvarchar(45), @eNote nvarchar(200);
DECLARE @created int = 0, @updated int = 0;

WHILE @seq <= @max
BEGIN
    SELECT @path = mtx_path, @serial = serial_no, @nvr = nvr_channel, @ip = ip_address, @note = note
    FROM @cam WHERE seq = @seq;

    SET @id = NULL;
    SELECT @id = camera_id, @name = name, @area = area, @sort = sort_order, @vis = is_visible,
           @eSerial = serial_no, @eNvr = nvr_channel, @eIp = ip_address, @eNote = note
    FROM cctv.cameras WHERE mtx_path = @path AND deleted_at IS NULL;

    IF @id IS NULL
    BEGIN
        EXEC cctv.SIS_Camera_Manage @Action = 'CREATE', @Name = @path, @MtxPath = @path,
             @IpAddress = @ip, @SerialNo = @serial, @NvrChannel = @nvr,
             @SortOrder = @seq, @IsVisible = 1, @Note = @note, @UserId = @UserId;
        SET @created += 1;
    END
    ELSE IF @eSerial IS NULL OR @eIp IS NULL OR (@eNvr IS NULL AND @nvr IS NOT NULL)
            OR (@eNote IS NULL AND @note IS NOT NULL)
    BEGIN
        SET @eSerial = ISNULL(@eSerial, @serial);
        SET @eIp     = ISNULL(@eIp, @ip);
        SET @eNvr    = ISNULL(@eNvr, @nvr);
        SET @eNote   = ISNULL(@eNote, @note);
        EXEC cctv.SIS_Camera_Manage @Action = 'UPDATE', @CameraId = @id, @Name = @name, @Area = @area,
             @IpAddress = @eIp, @SerialNo = @eSerial, @NvrChannel = @eNvr,
             @SortOrder = @sort, @IsVisible = @vis, @Note = @eNote, @UserId = @UserId;
        SET @updated += 1;
    END

    SET @seq += 1;
END

PRINT CONCAT('Kamera dibuat: ', @created, ', dilengkapi: ', @updated);
GO
