-- Prompt 35: (1) bundles.resource_person_name di-rename & direpurpose jadi bundles.remarks
-- (catatan bebas, diisi/diedit lewat BundleManager.razor -- bukan lagi identitas penjahit).
-- (2) employees.employee_code boleh NULL (penjahit yang belum punya kode tapi sudah mulai
-- kerja bisa didaftar dulu, kode diisi menyusul). Idempotent -- aman dijalankan berkali-kali.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1a. Rename kolom (hanya kalau belum di-rename sebelumnya).
IF COL_LENGTH('bundles', 'resource_person_name') IS NOT NULL
   AND COL_LENGTH('bundles', 'remarks') IS NULL
BEGIN
    EXEC sp_rename 'bundles.resource_person_name', 'remarks', 'COLUMN';
END
GO

-- 1b. Lebarkan tipe dari varchar(150) lama ke varchar(500) (konvensi kolom remarks di skema
-- ini, lihat header sql/create_tables_tmos_final.sql).
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bundles') AND name = 'remarks' AND max_length <> 500
)
BEGIN
    ALTER TABLE bundles ALTER COLUMN remarks VARCHAR(500) NULL;
END
GO

-- 2a. employees.employee_code jadi nullable.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('employees') AND name = 'employee_code' AND is_nullable = 0
)
BEGIN
    ALTER TABLE employees ALTER COLUMN employee_code VARCHAR(30) NULL;
END
GO

-- 2b. Index unik filtered semula tidak mengecualikan NULL -- SQL Server hanya mengizinkan
-- SATU baris NULL per unique index, jadi harus ditambah filter employee_code IS NOT NULL
-- supaya banyak karyawan tanpa kode bisa hidup berdampingan.
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('employees') AND name = 'UX_employees_code'
      AND filter_definition NOT LIKE '%employee_code%IS NOT NULL%'
)
BEGIN
    DROP INDEX UX_employees_code ON employees;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('employees') AND name = 'UX_employees_code'
)
BEGIN
    CREATE UNIQUE INDEX UX_employees_code ON employees(employee_code)
        WHERE deleted_at IS NULL AND employee_code IS NOT NULL;
END
GO
