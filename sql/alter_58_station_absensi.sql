-- Prompt 58 -- Absensi & Pegawai di Station: kolom kontak/nonaktif di employees +
-- tabel employee_attendances (absen harian manual oleh PIC line lewat perangkat stasiun).
-- Idempotent, dijalankan MANUAL.
--
-- Belum ada RFID: semua baris absen lahir dengan source = 'MANUAL'. Nanti data RFID mengisi
-- TABEL YANG SAMA dengan source = 'RFID' dan PIC tinggal mengoreksi -- karena itu kolom
-- source sudah disiapkan sekarang walau pengisinya belum ada.

-- ============ 1. employees: kontak + jejak nonaktif ============

-- No. telp disimpan HANYA digit (normalisasi di SP: buang non-digit, awalan 62 -> 0).
-- Dipakai station sebagai penanda "orang yang sama" saat menawarkan "Aktifkan lagi?".
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('employees') AND name = 'phone_no')
BEGIN
    ALTER TABLE employees ADD phone_no varchar(20) NULL;
END
GO

-- Tanggal terakhir kerja + alasan, diisi saat PIC menonaktifkan pegawai dari station
-- (RESIGN / HABIS_KONTRAK / DIBERHENTIKAN / PINDAH_DIVISI). Dikosongkan lagi saat diaktifkan.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('employees') AND name = 'inactive_date')
BEGIN
    ALTER TABLE employees ADD inactive_date date NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('employees') AND name = 'inactive_reason')
BEGIN
    ALTER TABLE employees ADD inactive_reason varchar(20) NULL;
END
GO

-- SENGAJA BUKAN UNIQUE: keunikan no. telp dicek di SP supaya nomor yang sudah dipakai
-- pegawai NONAKTIF bisa ditawarkan "Aktifkan lagi?" alih-alih ditolak index.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_employees_phone_no' AND object_id = OBJECT_ID('employees'))
BEGIN
    CREATE INDEX IX_employees_phone_no ON employees(phone_no)
        WHERE deleted_at IS NULL AND phone_no IS NOT NULL;
END
GO

-- ============ 2. employee_attendances ============

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'employee_attendances')
BEGIN
    CREATE TABLE employee_attendances(
     attendance_id int primary key identity(1,1),
     employee_id int not null
       constraint FK_ea_employees foreign key references employees(employee_id),
     attendance_date date not null,
     resource_id int not null                   -- line tempat absen DICATAT (bukan line pegawai saat ini)
       constraint FK_ea_resources foreign key references resources(resource_id),
     status char(1) not null                    -- H Hadir, I Izin, S Sakit, A Alpa, C Cuti
       constraint CK_ea_status check (status IN ('H','I','S','A','C')),
     check_in time(0) null,                     -- hanya boleh terisi kalau status = 'H'
     check_out time(0) null,                    -- boleh lebih kecil dari check_in (lewat tengah malam)
     note varchar(200) null,                    -- keterangan, mis. 'Surat dokter'
     source varchar(10) not null
       constraint DF_ea_source default 'MANUAL', -- MANUAL / RFID (RFID belum dipakai)
     station_id int null                        -- station yang TERAKHIR menyimpan
       constraint FK_ea_stations foreign key references stations(station_id),
     recorded_by_resource_id int not null       -- operator sesi saat pertama diisi
       constraint FK_ea_recorded_resource foreign key references resources(resource_id),
     updated_by_resource_id int null            -- operator sesi saat terakhir diubah
       constraint FK_ea_updated_resource foreign key references resources(resource_id),
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,                   -- user sistem station_system
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     -- Telat TIDAK disimpan (dihitung saat dibaca dari work_schedule_defaults). Jam hanya
     -- berlaku untuk Hadir -- status lain memaksa kedua kolom NULL di SP.
     constraint CK_ea_time_only_hadir check (status = 'H' OR (check_in IS NULL AND check_out IS NULL))
    );

    CREATE UNIQUE INDEX UX_ea_employee_date ON employee_attendances(employee_id, attendance_date)
        WHERE deleted_at IS NULL;
    CREATE INDEX IX_ea_resource_date ON employee_attendances(resource_id, attendance_date)
        WHERE deleted_at IS NULL;
END
GO
