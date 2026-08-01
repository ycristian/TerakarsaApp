-- Prompt 37 -- Planning Harian PPIC: jadwal, jumlah orang, target per tanggal per divisi
-- (+ per resource bila dashboard_mode = RESOURCE). Idempotent: aman dijalankan berulang.
-- Prasyarat: alter_36_dashboard_target.sql sudah dijalankan (dashboard_mode,
-- default_target_per_person, include_in_dashboard).

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'daily_division_plans')
BEGIN
    CREATE TABLE daily_division_plans(
     daily_division_plan_id int primary key identity(1,1),
     plan_date date not null,
     division_id int not null
       constraint FK_ddp_divisions foreign key references divisions(division_id),
     is_holiday bit not null default 0,         -- 1 = divisi libur pada tanggal ini
     start_time time(0) null,                   -- NULL bila libur
     end_time time(0) null,
     headcount int null,                        -- dipakai bila dashboard_mode = DIVISION
     target_per_person int null,                -- dipakai bila dashboard_mode = DIVISION
     remark varchar(500) null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );

    CREATE UNIQUE INDEX UX_ddp_date_division ON daily_division_plans(plan_date, division_id)
        WHERE deleted_at IS NULL;
    CREATE INDEX IX_ddp_plan_date ON daily_division_plans(plan_date) WHERE deleted_at IS NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'daily_resource_plans')
BEGIN
    CREATE TABLE daily_resource_plans(
     daily_resource_plan_id int primary key identity(1,1),
     daily_division_plan_id int not null
       constraint FK_drp_daily_division_plans foreign key references daily_division_plans(daily_division_plan_id),
     resource_id int not null
       constraint FK_drp_resources foreign key references resources(resource_id),
     headcount int not null default 0,
     target_per_person int not null default 0,
     start_time time(0) null,                   -- override; NULL = ikut jam divisi
     end_time time(0) null,                     -- override; NULL = ikut jam divisi
     remark varchar(500) null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );

    CREATE UNIQUE INDEX UX_drp_plan_resource ON daily_resource_plans(daily_division_plan_id, resource_id)
        WHERE deleted_at IS NULL;
END
GO
