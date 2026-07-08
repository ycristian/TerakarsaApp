/* =============================================================
   Seed data capture - snapshot of TerakarsaDb on 2026-07-08
   Generated from live data. Safe to re-run: each block clears
   the table (respecting FK order) before re-inserting.
   Excluded on purpose: RefreshTokens (session tokens, not seed
   data), ErrorLog (empty), and any table with zero rows.
   ============================================================= */

SET NOCOUNT ON;
GO

-- ============ CLEAR EXISTING DATA (reverse FK order) ============
DELETE FROM Products;
DELETE FROM article_workflows;
DELETE FROM workflow_template_steps;
DELETE FROM workflow_templates;
DELETE FROM article_photos;
DELETE FROM project_attachments;
DELETE FROM article_sizes;
DELETE FROM articles;
DELETE FROM size_pack_details;
DELETE FROM size_packs;
DELETE FROM projects;
DELETE FROM UserModules;
DELETE FROM employees;
DELETE FROM resources;
DELETE FROM Users;
DELETE FROM Modules;
DELETE FROM buyers;
DELETE FROM resource_types;
DELETE FROM positions;
DELETE FROM divisions;
GO

-- ============ divisions ============
SET IDENTITY_INSERT divisions ON;
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, N'CT', N'CUTTING', '2026-07-08 08:52:02.784', 1, NULL, NULL, NULL, NULL);
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, N'QT', N'QC&TRIMMING', '2026-07-08 08:52:35.910', 1, NULL, NULL, NULL, NULL);
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (3, N'SW', N'SEWING', '2026-07-08 08:52:48.458', 1, NULL, NULL, NULL, NULL);
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (4, N'DTF', N'Press DTF', '2026-07-08 08:53:12.909', 1, NULL, NULL, NULL, NULL);
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (5, N'PCK', N'Steam & Pack', '2026-07-08 08:53:29.278', 1, NULL, NULL, NULL, NULL);
INSERT INTO divisions (division_id, division_code, division_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (6, N'CORE', N'CORE', '2026-07-08 08:59:09.038', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT divisions OFF;
GO

-- ============ positions ============
SET IDENTITY_INSERT positions ON;
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, N'Supervisor', '2026-07-08 08:53:43.425', 1, NULL, NULL, NULL, NULL);
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, N'Merchandiser', '2026-07-08 08:53:48.616', 1, NULL, NULL, NULL, NULL);
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (3, N'Admin', '2026-07-08 08:53:55.021', 1, NULL, NULL, NULL, NULL);
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (4, N'Operator', '2026-07-08 08:53:58.720', 1, NULL, NULL, '2026-07-08 08:58:33.230', 1);
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (5, N'Operator', '2026-07-08 08:58:27.689', 1, NULL, NULL, NULL, NULL);
INSERT INTO positions (position_id, position_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (6, N'Developer', '2026-07-08 08:58:39.609', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT positions OFF;
GO

-- ============ resource_types ============
SET IDENTITY_INSERT resource_types ON;
INSERT INTO resource_types (resource_type_id, resource_type_code, resource_type_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, N'IN', N'Internal', '2026-07-08 08:54:13.529', 1, '2026-07-08 08:54:35.246', 1, NULL, NULL);
INSERT INTO resource_types (resource_type_id, resource_type_code, resource_type_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, N'OUT', N'Outsource', '2026-07-08 08:54:20.376', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT resource_types OFF;
GO

-- ============ buyers ============
SET IDENTITY_INSERT buyers ON;
INSERT INTO buyers (buyer_id, buyer_code, buyer_name, address, phone, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, N'CR001', N'Januar', N'Kopo Mas D37', N'08122313817', '2026-07-08 08:57:00.409', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT buyers OFF;
GO

-- ============ Modules ============
SET IDENTITY_INSERT Modules ON;
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (1, N'products', N'Produk1', N'Production', N'products', N'fe fe-package', 10, 1, '2026-06-20 21:40:29.743', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (2, N'counter', N'Counter', N'Production', N'counter', N'fe fe-hash', 20, 1, '2026-06-20 21:40:29.743', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (3, N'users', N'Kelola User', N'App Setting', N'users', N'fe fe-users', 30, 1, '2026-06-20 21:40:29.743', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (4, N'module-setting', N'Module Setting', N'App Setting', N'module-setting', N'fe fe-settings', 40, 1, '2026-06-20 21:40:29.743', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (5, N'module-access', N'Module Access', N'App Setting', N'module-access', N'fe fe-lock', 50, 1, '2026-06-20 21:40:29.747', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (6, N'MASTER_DIVISION', N'Divisi', N'App Setting', N'divisions', N'fe fe-layers', 100, 1, '2026-07-05 04:50:49.807', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (7, N'MASTER_POSITION', N'Jabatan', N'App Setting', N'positions', N'fe fe-briefcase', 110, 1, '2026-07-05 04:50:49.860', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (8, N'MASTER_RESOURCE_TYPE', N'Tipe Resource', N'App Setting', N'resource-types', N'fe fe-tool', 120, 1, '2026-07-05 04:50:49.860', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (9, N'MASTER_RESOURCE', N'Resource', N'App Setting', N'resources', N'fe fe-box', 130, 1, '2026-07-06 08:22:28.930', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (10, N'MASTER_BUYER', N'Buyer', N'App Setting', N'buyers', N'fe fe-shopping-bag', 140, 1, '2026-07-06 08:22:30.510', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (11, N'MASTER_EMPLOYEE', N'Karyawan', N'App Setting', N'employees', N'fe fe-users', 150, 1, '2026-07-06 08:25:49.987', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (12, N'ORDER_PROJECT', N'Project', N'Order', N'projects', N'fe fe-briefcase', 50, 1, '2026-07-06 16:23:24.073', NULL);
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (13, N'MASTER_SIZE_PACK', N'Size Pack', N'App Setting', N'size-packs', N'fe fe-maximize-2', 160, 1, '2026-07-07 19:43:01.320', N'Master Data');
INSERT INTO Modules (Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt, SubCategory) VALUES (14, N'MASTER_WORKFLOW', N'Workflow Template', N'App Setting', N'workflow-templates', N'fe fe-share-2', 170, 1, '2026-07-08 11:10:12.713', N'Master Data');
SET IDENTITY_INSERT Modules OFF;
GO

-- ============ Users ============
SET IDENTITY_INSERT Users ON;
INSERT INTO Users (Id, Username, Password, FullName, Role, IsActive, CreatedAt) VALUES (1, N'admin', N'3b612c75a7b5048a435fb6ec81e52ff92d6d795a8b5a9c17070f6a63c97a53b2', N'Administrator', N'Admin', 1, '2026-06-16 08:45:31.917');
INSERT INTO Users (Id, Username, Password, FullName, Role, IsActive, CreatedAt) VALUES (2, N'user1', N'a61a8adf60038792a2cb88e670b20540a9d6c2ca204ab754fc768950e79e7d36', N'User Test', N'User', 1, '2026-06-17 22:06:32.373');
INSERT INTO Users (Id, Username, Password, FullName, Role, IsActive, CreatedAt) VALUES (3, N'user2', N'a61a8adf60038792a2cb88e670b20540a9d6c2ca204ab754fc768950e79e7d36', N'User Two 1', N'User', 1, '2026-06-17 22:23:54.680');
INSERT INTO Users (Id, Username, Password, FullName, Role, IsActive, CreatedAt) VALUES (4, N'ivander', N'3cac8161c3c1cf8836cf9c46904420fb49aa743d6bf19300521cb37e66caf6a4', N'Yosef Ivander', N'Admin', 1, '2026-06-21 08:09:00.000');
SET IDENTITY_INSERT Users OFF;
GO

-- ============ resources ============
SET IDENTITY_INSERT resources ON;
INSERT INTO resources (resource_id, division_id, resource_type_id, resource_name, is_active, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 1, 1, N'Cutting Team', 1, '2026-07-08 08:54:47.159', 1, '2026-07-08 08:59:36.213', 1, NULL, NULL);
INSERT INTO resources (resource_id, division_id, resource_type_id, resource_name, is_active, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, 4, 1, N'DTF Team', 1, '2026-07-08 08:54:59.498', 1, '2026-07-08 08:59:40.573', 1, NULL, NULL);
INSERT INTO resources (resource_id, division_id, resource_type_id, resource_name, is_active, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (3, 2, 1, N'QC & Trim Team', 1, '2026-07-08 08:55:12.796', 1, '2026-07-08 08:59:47.437', 1, NULL, NULL);
INSERT INTO resources (resource_id, division_id, resource_type_id, resource_name, is_active, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (4, 5, 1, N'Steam & Pack Team', 1, '2026-07-08 08:56:08.740', 1, '2026-07-08 08:59:56.460', 1, NULL, NULL);
INSERT INTO resources (resource_id, division_id, resource_type_id, resource_name, is_active, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (5, 6, 1, N'Core Team', 1, '2026-07-08 08:59:24.726', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT resources OFF;
GO

-- ============ employees ============
SET IDENTITY_INSERT employees ON;
INSERT INTO employees (employee_id, division_id, resource_id, position_id, employee_code, employee_name, join_date, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 6, 5, 6, N'EM0001', N'Yosef Ivander', NULL, '2026-07-08 09:00:50.285', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT employees OFF;
GO

-- ============ UserModules ============
SET IDENTITY_INSERT UserModules ON;
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (1, 2, 2, '2026-06-20 21:40:29.767');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (2, 2, 1, '2026-06-20 21:40:29.767');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (3, 3, 2, '2026-06-20 21:40:29.770');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (4, 1, 5, '2026-06-20 21:40:29.787');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (5, 1, 4, '2026-06-20 21:40:29.787');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (6, 1, 3, '2026-06-20 21:40:29.787');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (7, 4, 1, '2026-06-21 08:09:15.097');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (8, 4, 3, '2026-06-21 08:09:15.097');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (9, 1, 6, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (10, 1, 7, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (11, 1, 8, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (12, 4, 6, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (13, 4, 7, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (14, 4, 8, '2026-07-05 04:50:49.977');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (15, 1, 9, '2026-07-06 08:22:29.017');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (16, 4, 9, '2026-07-06 08:22:29.017');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (17, 1, 10, '2026-07-06 08:22:30.530');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (18, 4, 10, '2026-07-06 08:22:30.530');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (19, 1, 11, '2026-07-06 08:25:50.010');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (20, 4, 11, '2026-07-06 08:25:50.010');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (24, 1, 12, '2026-07-06 16:23:24.110');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (25, 4, 12, '2026-07-06 16:23:24.110');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (26, 1, 13, '2026-07-07 19:43:01.340');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (27, 4, 13, '2026-07-07 19:43:01.340');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (28, 1, 14, '2026-07-08 11:10:12.737');
INSERT INTO UserModules (Id, UserId, ModuleId, CreatedAt) VALUES (29, 4, 14, '2026-07-08 11:10:12.737');
SET IDENTITY_INSERT UserModules OFF;
GO

-- ============ projects ============
SET IDENTITY_INSERT projects ON;
INSERT INTO projects (project_id, customer_id, project_md, project_pic, project_name, no_po, order_date, start_date, deadline, delivery_date, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 1, 1, 1, N'Project A', NULL, '2026-07-08', NULL, '2026-07-22', NULL, '2026-07-08 09:20:23.055', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT projects OFF;
GO

-- ============ size_packs ============
SET IDENTITY_INSERT size_packs ON;
INSERT INTO size_packs (size_pack_id, buyer_id, size_pack_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, NULL, N'Kaos Reguler - AGS', '2026-07-08 09:02:14.156', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT size_packs OFF;
GO

-- ============ size_pack_details ============
SET IDENTITY_INSERT size_pack_details ON;
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 1, N'S', 2, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, 1, N'M', 3, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (3, 1, N'L', 4, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (4, 1, N'XL', 5, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (5, 1, N'XXL', 6, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
INSERT INTO size_pack_details (size_pack_detail_id, size_pack_id, size_name, sort_order, description, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (6, 1, N'XS', 1, NULL, '2026-07-08 09:02:14.158', 1, NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT size_pack_details OFF;
GO

-- ============ articles ============
SET IDENTITY_INSERT articles ON;
INSERT INTO articles (article_id, project_id, size_pack_id, article_name, style, color, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 1, 1, N'Kaos Hitam', N'Kaos', N'Hitam', '2026-07-08 09:21:08.770', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
SET IDENTITY_INSERT articles OFF;
GO

-- ============ article_sizes ============
SET IDENTITY_INSERT article_sizes ON;
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, 1, 6, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (2, 1, 1, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (3, 1, 2, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (4, 1, 3, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (5, 1, 4, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
INSERT INTO article_sizes (article_size_id, article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (6, 1, 5, 6, 6, '2026-07-08 09:21:08.787', 1, '2026-07-08 10:12:00.705', 1, NULL, NULL);
SET IDENTITY_INSERT article_sizes OFF;
GO

-- ============ project_attachments ============
SET IDENTITY_INSERT project_attachments ON;
INSERT INTO project_attachments (project_attachment_id, project_id, file_name, file_path, file_size_kb, file_type, description, sort_order, created_at, created_by, deleted_at, deleted_by) VALUES (1, 1, N'Blank T-Shirt_thumb_900x900 x.jpg', N'projects/1/57bde9bb-3294-4e77-ade4-3240b66110b7.jpg', 29, N'jpg', NULL, 1, '2026-07-08 09:22:11.777', 1, NULL, NULL);
INSERT INTO project_attachments (project_attachment_id, project_id, file_name, file_path, file_size_kb, file_type, description, sort_order, created_at, created_by, deleted_at, deleted_by) VALUES (2, 1, N'LogoTerakarsa - Copy.jpg', N'projects/1/1db8d16c-c17a-4808-b75a-35caf1cb7827.jpg', 21, N'jpg', NULL, 2, '2026-07-08 09:22:27.009', 1, NULL, NULL);
SET IDENTITY_INSERT project_attachments OFF;
GO

-- ============ article_photos ============
SET IDENTITY_INSERT article_photos ON;
INSERT INTO article_photos (article_photo_id, article_id, file_name, file_path, file_size_kb, sort_order, is_primary, created_at, created_by, deleted_at, deleted_by) VALUES (1, 1, N'Blank T-Shirt_thumb_900x900 x.jpg', N'articles/1/e0f5861e-1879-4323-ad56-134ade02e9aa.jpg', 29, 1, 1, '2026-07-08 09:21:19.635', 1, NULL, NULL);
INSERT INTO article_photos (article_photo_id, article_id, file_name, file_path, file_size_kb, sort_order, is_primary, created_at, created_by, deleted_at, deleted_by) VALUES (2, 1, N'LogoTerakarsa.jpg', N'articles/1/24ed726e-424f-4fbb-869f-4087b487d0b7.jpg', 45, 2, 0, '2026-07-08 09:21:33.353', 1, NULL, NULL);
SET IDENTITY_INSERT article_photos OFF;
GO

-- ============ workflow_templates ============
SET IDENTITY_INSERT workflow_templates ON;
INSERT INTO workflow_templates (workflow_template_id, workflow_code, workflow_name, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (1, N'Normal', N'Normal', '2026-07-08 11:16:00.833', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL);
SET IDENTITY_INSERT workflow_templates OFF;
GO

-- ============ workflow_template_steps ============
SET IDENTITY_INSERT workflow_template_steps ON;
INSERT INTO workflow_template_steps (step_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (1, 1, N'Cutting', 1, 1, '2026-07-08 11:16:00.839', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL, 0);
INSERT INTO workflow_template_steps (step_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (2, 1, N'Sewing', 3, 2, '2026-07-08 11:16:00.839', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL, 1);
INSERT INTO workflow_template_steps (step_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (3, 1, N'Trim & QC', 2, 3, '2026-07-08 11:16:00.839', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL, 1);
INSERT INTO workflow_template_steps (step_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (4, 1, N'Press DTF', 4, 4, '2026-07-08 11:16:00.839', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL, 1);
INSERT INTO workflow_template_steps (step_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (5, 1, N'Steam & Packing', 5, 5, '2026-07-08 11:16:00.839', 1, '2026-07-08 11:46:09.626', 1, NULL, NULL, 1);
SET IDENTITY_INSERT workflow_template_steps OFF;
GO

-- ============ article_workflows ============
SET IDENTITY_INSERT article_workflows ON;
INSERT INTO article_workflows (article_workflow_id, article_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (1, 1, 1, N'Cutting', 1, 1, '2026-07-08 11:16:30.900', 1, '2026-07-08 11:46:32.030', 1, NULL, NULL, 0);
INSERT INTO article_workflows (article_workflow_id, article_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (2, 1, 1, N'Sewing', 3, 2, '2026-07-08 11:16:30.900', 1, '2026-07-08 11:46:32.030', 1, NULL, NULL, 1);
INSERT INTO article_workflows (article_workflow_id, article_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (3, 1, 1, N'Trim & QC', 2, 3, '2026-07-08 11:16:30.900', 1, '2026-07-08 11:46:32.030', 1, NULL, NULL, 1);
INSERT INTO article_workflows (article_workflow_id, article_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (4, 1, 1, N'Press DTF', 4, 4, '2026-07-08 11:16:30.900', 1, '2026-07-08 11:46:32.030', 1, NULL, NULL, 1);
INSERT INTO article_workflows (article_workflow_id, article_id, workflow_template_id, step_name, division_id, sort_order, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by, requires_bundle) VALUES (5, 1, 1, N'Steam & Packing', 5, 5, '2026-07-08 11:16:30.900', 1, '2026-07-08 11:46:32.030', 1, NULL, NULL, 1);
SET IDENTITY_INSERT article_workflows OFF;
GO

-- ============ Products ============
SET IDENTITY_INSERT Products ON;
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (1, N'Laptop Asus ROG', 9500000.00, 8, 0, '2026-06-17 11:43:08.140');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (2, N'Mouse Logitech', 150000.00, 25, 1, '2026-06-17 11:53:56.387');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (3, N'Keyboard Keychron 1', 1000000.00, 10, 1, '2026-06-17 12:01:24.637');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (4, N'Laptop Asus', 20000.00, 2, 1, '2026-06-17 12:09:54.493');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (5, N'asdasddsad', 1.00, 0, 0, '2026-06-17 21:14:24.793');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (6, N'asdsadasd', 21.00, 0, 0, '2026-06-17 21:14:28.050');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (7, N'adasdsadas', 1.00, 0, 0, '2026-06-17 21:14:32.127');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (8, N'fasdfasdfa', 1.00, 0, 0, '2026-06-17 21:14:35.290');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (9, N'adsad', 1.00, 0, 0, '2026-06-17 21:14:38.210');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (10, N'fdsafdasdf1', 11.00, 0, 0, '2026-06-17 21:14:43.600');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (11, N'asdsadfas', 1111.00, 0, 0, '2026-06-17 21:14:47.237');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (12, N'sadfasfsdfasdfsd', 11213.00, 0, 0, '2026-06-17 21:14:52.693');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (13, N'asd', 1.00, 0, 1, '2026-06-18 12:25:22.667');
INSERT INTO Products (Id, Name, Price, Stock, IsActive, CreatedAt) VALUES (14, N'asd', 1.00, 0, 0, '2026-06-18 12:26:43.637');
SET IDENTITY_INSERT Products OFF;
GO

