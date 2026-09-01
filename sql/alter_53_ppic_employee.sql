-- Prompt 53: module PPIC Karyawan + status aktif/nonaktif + kode karyawan otomatis.
-- Idempotent, dijalankan manual.

-- Divisi yang boleh dikelola PPIC (checkbox "Dikelola PPIC" di Master Divisi).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('divisions') AND name = 'ppic_managed')
BEGIN
    ALTER TABLE divisions
      ADD ppic_managed bit NOT NULL CONSTRAINT DF_divisions_ppic_managed DEFAULT 0;
END
GO

-- Status aktif karyawan -- nonaktif = tidak muncul di dropdown employee, data lama tetap utuh.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('employees') AND name = 'is_active')
BEGIN
    ALTER TABLE employees
      ADD is_active bit NOT NULL CONSTRAINT DF_employees_is_active DEFAULT 1;
END
GO
