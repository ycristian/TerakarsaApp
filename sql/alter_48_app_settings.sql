-- Ad hoc (lanjutan Prompt 41 kupon borongan): tabel app_settings sebagai saklar master
-- auto-print kupon borongan, terpisah dari flag per-step print_kupon. auto_print_coupon_active
-- = 0 mematikan SEMUA insert print_jobs job_type = 'KUPON_BORONGAN' di jalur otomatis
-- (CREATE/RECEIVE/REVISE_HANDOVER auto-terima) di seluruh sistem, tanpa menyentuh flag
-- print_kupon per step -- tinggal set balik ke 1 utk nyalakan lagi. TIDAK memengaruhi tombol
-- manual "Print Hasil" (SIS_WorkflowLog_PrintHasil) -- itu aksi eksplisit operator, bukan
-- auto-print. Baris tunggal (id = 1), bukan key-value -- baru satu setting yang dibutuhkan.
-- Idempotent: aman dijalankan berkali-kali.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'app_settings')
BEGIN
    CREATE TABLE app_settings(
        app_setting_id int primary key identity(1,1),
        auto_print_coupon_active bit not null default 1,
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

-- Seed baris tunggal (hanya kalau belum ada baris hidup sama sekali).
IF NOT EXISTS (SELECT 1 FROM app_settings WHERE deleted_at IS NULL)
    INSERT INTO app_settings (auto_print_coupon_active, created_at, created_by)
    SELECT 1, SYSDATETIME(), (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
GO
