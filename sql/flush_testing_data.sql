-- Flush data testing project/article/size/workflow (bundle, workflow log, print job, pack).
-- TIDAK menyentuh template: size_packs/size_pack_details (template ukuran) dan
-- workflow_templates/workflow_template_steps (template workflow) tetap utuh.
-- Urutan DELETE mengikuti FK child -> parent. cost_transactions ikut dihapus karena
-- project_id di tabel itu NOT NULL (tidak bisa hapus projects tanpa ini).
-- Jalankan manual di lingkungan testing saja.

SET NOCOUNT ON;

DELETE FROM pack_items;
DELETE FROM packs;
DELETE FROM print_jobs;
DELETE FROM article_workflow_logs;
DELETE FROM bundles;
DELETE FROM cost_transactions;
DELETE FROM article_workflows;
DELETE FROM article_photos;
DELETE FROM article_sizes;
DELETE FROM project_attachments;
DELETE FROM articles;
DELETE FROM projects;

-- reset identity supaya nomor mulai bersih lagi dari 1 untuk sesi testing berikutnya
DBCC CHECKIDENT ('pack_items', RESEED, 0);
DBCC CHECKIDENT ('packs', RESEED, 0);
DBCC CHECKIDENT ('print_jobs', RESEED, 0);
DBCC CHECKIDENT ('article_workflow_logs', RESEED, 0);
DBCC CHECKIDENT ('bundles', RESEED, 0);
DBCC CHECKIDENT ('cost_transactions', RESEED, 0);
DBCC CHECKIDENT ('article_workflows', RESEED, 0);
DBCC CHECKIDENT ('article_photos', RESEED, 0);
DBCC CHECKIDENT ('article_sizes', RESEED, 0);
DBCC CHECKIDENT ('project_attachments', RESEED, 0);
DBCC CHECKIDENT ('articles', RESEED, 0);
DBCC CHECKIDENT ('projects', RESEED, 0);
