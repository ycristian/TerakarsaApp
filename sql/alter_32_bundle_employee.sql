-- Prompt 32: Penjahit Bundle -- Teks Bebas -> Master Employee.
-- Hanya ADD kolom nullable + FK, idempotent, aman dijalankan berulang. Kolom
-- resource_person_name TIDAK dihapus -- tetap dipakai sebagai fallback tampilan untuk
-- bundle lama sampai mapping manual ke employee_id selesai (prompt terpisah nanti).

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bundles') AND name = 'employee_id'
)
BEGIN
    ALTER TABLE bundles ADD employee_id int null;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bundles_employees'
)
BEGIN
    ALTER TABLE bundles
        ADD CONSTRAINT FK_bundles_employees FOREIGN KEY (employee_id) REFERENCES employees(employee_id);
END
GO
