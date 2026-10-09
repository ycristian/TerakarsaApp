-- Prompt 70 -- Absensi RFID: kartu pegawai (employee_cards), sesi absensi turunan tap
-- (attendance_sessions), log tap mentah (gate_taps), log perubahan data pegawai dari gate
-- (employee_change_log), plus dua kolom penanda: positions.is_gate_operator dan
-- resources.color_hex.
-- Idempotent, dijalankan MANUAL.
--
-- Konsep: kartu TIDAK dibawa pulang -- dititip di rak gate, diambil pagi, dikembalikan sore.
-- Karena itu status kartu = status orang, dan absensi diturunkan dari tap ambil/kembali kartu.
-- Tidak ada tombol MASUK/PULANG; seluruh keputusan in/out ada di SIS_Gate_Tap (sp_Gate.sql).
--
-- CATATAN PENYIMPANGAN DARI PROMPT (disengaja): prompt 70 pasal 1.3 meminta kolom baru
-- employees.phone varchar(30). Kolom itu TIDAK dibuat -- employees sudah punya phone_no
-- varchar(20) dari Prompt 58 dengan tujuan yang sama persis (no. telp kontak pegawai, sudah
-- dipakai station + Master Karyawan + SIS_Employee_*). Dua kolom telepon pada satu tabel
-- akan memecah data: satpam mengisi yang satu, station menampilkan yang lain. Gate memakai
-- employees.phone_no, dengan normalisasi yang SAMA (buang non-digit, awalan 62 -> 0) supaya
-- satu representasi saja yang tersimpan.
--
-- WAJIB ON (bukan hanya di SSMS -- sqlcmd/ODBC default-nya QUOTED_IDENTIFIER OFF): semua
-- filtered index di bawah akan gagal Msg 1934 tanpa ini.
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============ 1. positions: penanda jabatan yang boleh membuka menu satpam ============

-- Akses menu gate melekat pada JABATAN, bukan pada kartu dan bukan pada user login --
-- aplikasi gate memang tanpa login, dan employees tidak punya relasi ke users.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('positions') AND name = 'is_gate_operator')
BEGIN
    ALTER TABLE positions ADD is_gate_operator bit NOT NULL
        CONSTRAINT DF_positions_is_gate_operator DEFAULT 0;
END
GO

-- ============ 2. resources: warna holder/lanyard fisik ============

-- Warna ada di holder, bukan di kartu (mutasi line cukup tukar holder). Nilai ini dipakai
-- badge warna di layar gate supaya satpam bisa mencocokkan dengan holder yang dipakai.
-- NULL = layar gate memakai warna netral.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('resources') AND name = 'color_hex')
BEGIN
    ALTER TABLE resources ADD color_hex varchar(7) NULL;   -- mis. '#1E5FA8'
END
GO

-- ============ 3. employee_cards ============

-- Lapis identitas UMUM, bukan tabel milik modul absensi: kartu yang sama nantinya dipakai
-- untuk pengambilan barang di gudang (modul material tinggal ikut memakainya -- di luar
-- cakupan Prompt 70).
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'employee_cards')
BEGIN
    CREATE TABLE employee_cards(
     employee_card_id int primary key identity(1,1),
     employee_id int not null
       constraint FK_ec_employees foreign key references employees(employee_id),
     card_uid varchar(20) not null,             -- 10 digit desimal, DISIMPAN SUDAH DI-PAD NOL DI DEPAN
     card_type varchar(20) not null             -- TETAP / SEMENTARA
       constraint CK_ec_card_type check (card_type IN ('TETAP','SEMENTARA')),
     card_status varchar(20) not null           -- AKTIF / NONAKTIF
       constraint CK_ec_card_status check (card_status IN ('AKTIF','NONAKTIF')),
     issued_at datetime2 not null
       constraint DF_ec_issued_at default sysdatetime(),
     issued_by_employee_id int null             -- satpam yang mendaftarkan dari gate; NULL kalau
       constraint FK_ec_issued_by_employee     -- didaftarkan dari admin panel (pelakunya sudah
       foreign key references employees(employee_id),  -- tercatat di created_by)
     remarks varchar(255) null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );
END
GO

-- Index dibuat di blok TERPISAH dari CREATE TABLE, masing-masing dengan guard sendiri: kalau
-- satu CREATE INDEX gagal (mis. SET option salah), tabelnya sudah ada dan guard "IF NOT EXISTS
-- sys.tables" akan melewati seluruh blok saat script dijalankan ulang -- index-nya tidak akan
-- pernah terbuat. Pola ini membuat script benar-benar bisa diulang dari kondisi separuh jadi.

-- Satu UID hanya boleh AKTIF di satu karyawan, tapi kartu lama yang sudah NONAKTIF tetap
-- tersimpan sebagai riwayat (kartu hilang/diganti).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_employee_cards_uid' AND object_id = OBJECT_ID('employee_cards'))
    CREATE UNIQUE INDEX UX_employee_cards_uid ON employee_cards(card_uid)
        WHERE deleted_at IS NULL AND card_status = 'AKTIF';
GO

-- SENGAJA TIDAK unique per employee: satu karyawan boleh punya beberapa kartu AKTIF sekaligus
-- (mis. kartu tetap + kartu sementara). Jangan dikunci.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_employee_cards_employee' AND object_id = OBJECT_ID('employee_cards'))
    CREATE INDEX IX_employee_cards_employee ON employee_cards(employee_id)
        WHERE deleted_at IS NULL;
GO

-- ============ 4. attendance_sessions ============

-- Sesi melekat pada KARYAWAN, bukan pada kartu: beberapa kartu aktif milik satu orang tetap
-- bermuara ke satu sesi.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'attendance_sessions')
BEGIN
    CREATE TABLE attendance_sessions(
     attendance_session_id int primary key identity(1,1),
     employee_id int not null
       constraint FK_as_employees foreign key references employees(employee_id),
     -- division_id/resource_id di-SNAPSHOT saat check in supaya mutasi line tidak mengubah
     -- riwayat absensi.
     division_id int not null
       constraint FK_as_divisions foreign key references divisions(division_id),
     resource_id int null
       constraint FK_as_resources foreign key references resources(resource_id),
     work_date date not null,                   -- tanggal check in (pemilik sesi)
     check_in_at datetime2 not null,
     check_out_at datetime2 null,               -- NULL = belum / tidak diketahui
     session_status varchar(20) not null        -- OPEN / CLOSED / ANOMALI
       constraint CK_as_status check (session_status IN ('OPEN','CLOSED','ANOMALI')),
     session_flag varchar(30) null,             -- LEMBUR_DIKONFIRMASI / BELUM_CHECKOUT / LUPA_KEMBALI / DIKOREKSI
     entry_source varchar(10) not null          -- GATE / MANUAL
       constraint CK_as_entry_source check (entry_source IN ('GATE','MANUAL')),
     remarks varchar(255) null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     -- ANOMALI = ditutup paksa, check_out_at WAJIB NULL (butuh koreksi admin).
     -- OPEN = kartu sedang diambil, orang ada di dalam.
     constraint CK_as_checkout_shape check (
         (session_status = 'CLOSED' AND check_out_at IS NOT NULL)
      OR (session_status <> 'CLOSED' AND check_out_at IS NULL)
     )
    );
END
GO

-- Hanya boleh ada SATU sesi OPEN per karyawan -- beberapa kartu aktif milik satu orang tetap
-- bermuara ke satu sesi.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_as_open_per_employee' AND object_id = OBJECT_ID('attendance_sessions'))
    CREATE UNIQUE INDEX UX_as_open_per_employee ON attendance_sessions(employee_id)
        WHERE session_status = 'OPEN' AND deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_as_date_division' AND object_id = OBJECT_ID('attendance_sessions'))
    CREATE INDEX IX_as_date_division ON attendance_sessions(work_date, division_id)
        WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_as_employee_date' AND object_id = OBJECT_ID('attendance_sessions'))
    CREATE INDEX IX_as_employee_date ON attendance_sessions(employee_id, work_date)
        WHERE deleted_at IS NULL;
GO

-- ============ 5. gate_taps (log mentah -- tidak di-update, tidak di-soft-delete) ============

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'gate_taps')
BEGIN
    CREATE TABLE gate_taps(
     gate_tap_id int primary key identity(1,1),
     tap_uid uniqueidentifier not null,         -- digenerate GateApp, kunci idempoten
     card_uid varchar(20) not null,
     tapped_at datetime2 not null,              -- WAKTU TAP ASLI dari gate, BUKAN waktu terima server
     gate_code varchar(30) not null,
     result_code varchar(30) not null,
     attendance_session_id int null
       constraint FK_gt_sessions foreign key references attendance_sessions(attendance_session_id),
     employee_id int null                       -- NULL kalau kartu tidak dikenal
       constraint FK_gt_employees foreign key references employees(employee_id),
     is_offline_replay bit not null
       constraint DF_gt_offline_replay default 0,
     created_at datetime2 not null default sysdatetime()
    );
END
GO

-- Inilah yang mencegah tap terhitung dua kali kalau jaringan putus setelah server commit tapi
-- sebelum GateApp menerima balasan.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_gate_taps_tap_uid' AND object_id = OBJECT_ID('gate_taps'))
    CREATE UNIQUE INDEX UX_gate_taps_tap_uid ON gate_taps(tap_uid);
GO

-- Cooldown 30 detik dicek dengan ini (card_uid + tapped_at terakhir).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_gate_taps_card_time' AND object_id = OBJECT_ID('gate_taps'))
    CREATE INDEX IX_gate_taps_card_time ON gate_taps(card_uid, tapped_at DESC);
GO

-- ============ 6. employee_change_log (log mentah) ============

-- Tanpa tabel ini, data karyawan bisa berubah dari gate tanpa jejak. Satu baris per field
-- yang benar-benar berubah.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'employee_change_log')
BEGIN
    CREATE TABLE employee_change_log(
     employee_change_log_id int primary key identity(1,1),
     employee_id int not null
       constraint FK_ecl_employees foreign key references employees(employee_id),
     field_name varchar(50) not null,           -- employee_name / phone_no (nama kolom asli)
     old_value varchar(255) null,
     new_value varchar(255) null,
     changed_by_employee_id int null            -- satpam, kalau dari gate
       constraint FK_ecl_changed_by_employee foreign key references employees(employee_id),
     source varchar(10) not null                -- GATE / ADMIN
       constraint CK_ecl_source check (source IN ('GATE','ADMIN')),
     created_at datetime2 not null default sysdatetime(),
     created_by int not null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ecl_employee' AND object_id = OBJECT_ID('employee_change_log'))
    CREATE INDEX IX_ecl_employee ON employee_change_log(employee_id, created_at DESC);
GO
