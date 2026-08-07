-- Ganti label Category "App Setting" jadi "Setting" untuk Kelola User, Module
-- Setting, Module Access, Kelola Stasiun, Dashboard TV, dan seluruh isi folder
-- "Master Data" (Divisi, Jabatan, Tipe Resource, Resource, Buyer, Karyawan,
-- Size Pack, Workflow Template, Jam Kerja & Target) — supaya semuanya bisa
-- dikelompokkan jadi 1 menu utama collapsible "Setting" di sidebar.
-- Idempotent: aman dijalankan berulang (no-op setelah baris pertama kali di-update).

UPDATE Modules
SET Category = 'Setting'
WHERE Category = 'App Setting';
GO
