/* =============================================================
   Prompt 77 -- module PRINT_ADMIN: halaman /admin/printer.
   Isinya tabel print_job_routes dengan dropdown device per job_type, supaya owner
   memindahkan THREAD_SKU_LABEL / THREAD_SPLIT_LABEL ke HP (atau kembali ke printer
   PC) TANPA SQL.

   Belum ada module printer sebelumnya (jalur Prompt 48 diatur lewat SQL manual),
   jadi module baru ini di-seed di sini. Category "Sistem" bersama SUPER_ADMIN &
   UNLOCK_REQUEST: isinya pengaturan perangkat, bukan pekerjaan harian.

   Endpoint-nya sendiri sudah dibatasi [Authorize(Roles = "Admin")] di
   PrintAdminController, jadi module ini hanya mengatur tampil/tidaknya menu.

   Idempotent.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'PRINT_ADMIN')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('PRINT_ADMIN', 'Printer & Routing', 'Sistem', NULL, 'admin/printer', 'fe fe-printer', 880, 1, GETDATE());
GO

-- Assign ke seluruh user Role = Admin (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'PRINT_ADMIN'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

SELECT Code, Name, Category, Route, SortOrder FROM Modules WHERE Code = 'PRINT_ADMIN';
GO
