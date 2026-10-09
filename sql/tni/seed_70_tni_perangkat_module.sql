-- Module halaman PENGELOLAAN perangkat & petugas PDH TNI AD (2026-10-02).
--
-- Perlu entri sendiri karena route module TNI_PDH ('tni') kini mengarah ke
-- beranda PERANGKAT yang digerbangi kode pairing -- admin yang login di desktop
-- tidak bisa lewat sana. Halaman ini SELALU butuh login + module TNI_PDH.
--
-- Dari sini admin membuat kode pairing (yang memberi sebuah tablet akses tanpa
-- login) dan mendaftarkan petugas.
--
-- Memakai Code TNI_PDH sebagai syarat akses halamannya; entri module ini murni
-- supaya link-nya muncul di sidebar.
-- Idempotent: aman dijalankan berulang.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'TNI_PDH_PERANGKAT')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('TNI_PDH_PERANGKAT', 'Perangkat PDH TNI', 'Order', NULL, 'tni/perangkat', 'fe fe-tablet', 59, 1, GETDATE());
GO

INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'TNI_PDH_PERANGKAT'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

SELECT Code, Name, Route, SortOrder FROM Modules WHERE Code LIKE 'TNI_PDH%' ORDER BY SortOrder;
GO
