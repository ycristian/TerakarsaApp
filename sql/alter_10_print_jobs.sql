-- Migrasi untuk DB yang sudah ada: tabel print_jobs (antrian cetak label) + index.
-- Idempotent, aman dijalankan berulang. Tabel bundles sudah ada sejak Prompt 7b/8.

IF OBJECT_ID('print_jobs', 'U') IS NULL
BEGIN
    CREATE TABLE print_jobs(
     print_job_id int primary key identity(1,1),
     job_type varchar(30) not null,
     ref_id int not null,
     payload nvarchar(max) not null,
     [status] varchar(20) not null default 'PENDING',
     error_message varchar(500) null,
     retry_count int not null default 0,
     printed_at datetime2 null,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_print_jobs_status' AND object_id = OBJECT_ID('print_jobs'))
    CREATE INDEX IX_print_jobs_status ON print_jobs([status]) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_print_jobs_ref' AND object_id = OBJECT_ID('print_jobs'))
    CREATE INDEX IX_print_jobs_ref ON print_jobs(job_type, ref_id) WHERE deleted_at IS NULL;
GO
