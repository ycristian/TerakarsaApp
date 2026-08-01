-- Prompt 36 -- Fondasi Dashboard Target: flag divisi/resource + setting jam kerja default.
-- Idempotent: aman dijalankan berulang. HANYA skema -- tidak ada SP di file ini
-- (lihat sp_WorkScheduleDefault_Manage.sql / sp_WorkScheduleDefault_Select.sql).

-- 1a. Kolom baru di divisions
IF COL_LENGTH('divisions', 'show_in_dashboard') IS NULL
    ALTER TABLE divisions ADD show_in_dashboard BIT NOT NULL CONSTRAINT DF_divisions_show_in_dashboard DEFAULT 1;
GO

IF COL_LENGTH('divisions', 'dashboard_mode') IS NULL
    ALTER TABLE divisions ADD dashboard_mode VARCHAR(20) NOT NULL CONSTRAINT DF_divisions_dashboard_mode DEFAULT 'DIVISION';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints WHERE name = 'CK_divisions_dashboard_mode'
)
    ALTER TABLE divisions ADD CONSTRAINT CK_divisions_dashboard_mode CHECK (dashboard_mode IN ('DIVISION', 'RESOURCE'));
GO

IF COL_LENGTH('divisions', 'dashboard_sort_order') IS NULL
    ALTER TABLE divisions ADD dashboard_sort_order INT NOT NULL CONSTRAINT DF_divisions_dashboard_sort_order DEFAULT 0;
GO

IF COL_LENGTH('divisions', 'default_target_per_person') IS NULL
    ALTER TABLE divisions ADD default_target_per_person INT NOT NULL CONSTRAINT DF_divisions_default_target_per_person DEFAULT 0;
GO

-- 1b. Kolom baru di resources
IF COL_LENGTH('resources', 'include_in_dashboard') IS NULL
    ALTER TABLE resources ADD include_in_dashboard BIT NOT NULL CONSTRAINT DF_resources_include_in_dashboard DEFAULT 1;
GO

-- 1c. Tabel baru work_schedule_defaults -- jam kerja default per divisi per hari.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'work_schedule_defaults')
BEGIN
    CREATE TABLE work_schedule_defaults(
     work_schedule_default_id int primary key identity(1,1),
     division_id int not null
       constraint FK_wsd_divisions foreign key references divisions(division_id),
     day_of_week tinyint not null,              -- 1 = Senin ... 7 = Minggu
     is_working_day bit not null default 1,     -- 0 = libur default (mis. Minggu)
     start_time time(0) not null,
     end_time time(0) not null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     constraint CK_wsd_day_of_week check (day_of_week between 1 and 7)
    );

    CREATE UNIQUE INDEX UX_wsd_division_day ON work_schedule_defaults(division_id, day_of_week)
        WHERE deleted_at IS NULL;
END
GO

-- 1d. Tabel baru work_break_defaults -- rentang istirahat sistem-wide (boleh dibatasi ke hari tertentu).
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'work_break_defaults')
BEGIN
    CREATE TABLE work_break_defaults(
     work_break_default_id int primary key identity(1,1),
     break_name varchar(150) not null,          -- mis. 'Istirahat Siang'
     day_of_week tinyint null,                  -- NULL = berlaku semua hari
     start_time time(0) not null,
     end_time time(0) not null,
     sort_order int not null default 0,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     constraint CK_wbd_day_of_week check (day_of_week is null or day_of_week between 1 and 7)
    );
END
GO
