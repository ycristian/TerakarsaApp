/* =============================================================
   TMOS - Skema Final
   Aturan yang diterapkan konsisten di semua tabel:
   1. varchar spesifik: code(30), name(150), status(20), lot(50),
      serial(20), remarks(500), delete_reason(255)
   2. Kolom wajib bisnis = NOT NULL (name, code, FK utama)
   3. Semua FK diberi nama (FK_anak_induk) agar mudah di-ALTER
   4. Kode unik via filtered unique index (kode bisa dipakai ulang
      setelah baris lama di-soft-delete)
   5. money -> decimal(19,4), semua qty pecahan -> decimal(18,4)
   6. order_id (urutan) -> sort_order, agar tidak rancu dengan FK
   7. Tabel log (article_workflow_logs, material_movement):
      tanpa updated_*, ada delete_reason
   8. material_stocks: current_qty DIHAPUS (dihitung via view)
   9. created_by/updated_by/deleted_by: FK ke users menyusul
      setelah migrasi tabel auth (Fase 0)
   ============================================================= */

-- ============ 1. MASTER TANPA DEPENDENSI ============

CREATE TABLE buyers (
 buyer_id int primary key identity(1,1),
 buyer_code varchar(30) not null,
 buyer_name varchar(150) not null,
 [address] varchar(255) null,
 phone varchar(30) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE divisions(
 division_id int primary key identity(1,1),
 division_code varchar(30) not null,
 division_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE positions(
 position_id int primary key identity(1,1),
 position_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE resource_types(
 resource_type_id int primary key identity(1,1),
 resource_type_code varchar(30) not null,   -- sebelumnya resource_code, disamakan polanya
 resource_type_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE suppliers (
 supplier_id int primary key identity(1,1),
 supplier_code varchar(30) not null,
 supplier_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE units(
 unit_id int primary key identity(1,1),
 unit_name varchar(50) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- FABRIC, ACCESSORY, CONSUMABLE, PACKAGING, CHEMICAL
CREATE TABLE material_categories(
 material_category_id int primary key identity(1,1),
 category_code varchar(30) not null,
 category_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Fabric, Thread, Labor, Electricity, dll
CREATE TABLE cost_components(
 cost_component_id int primary key identity(1,1),
 cost_component_code varchar(30) not null,
 cost_component_name varchar(150) not null,
 is_direct bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE material_movement_types(
 movement_type_id int primary key identity(1,1),
 movement_type_code varchar(30) not null,
 movement_type_name varchar(150) not null,
 stock_effect smallint not null,            -- +1 menambah stok, -1 mengurangi (tinyint tidak bisa negatif)
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE material_adjustment_types(
 adjustment_type_id int primary key identity(1,1),
 adjustment_type_code varchar(30) not null,
 adjustment_type_name varchar(150) not null,
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 2. MASTER DENGAN DEPENDENSI ============

CREATE TABLE resources(
 resource_id int primary key identity(1,1),
 division_id int not null
   constraint FK_resources_divisions foreign key references divisions(division_id),
 resource_type_id int not null
   constraint FK_resources_resource_types foreign key references resource_types(resource_type_id),
 resource_name varchar(150) not null,
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE employees(
 employee_id int primary key identity(1,1),
 division_id int not null
   constraint FK_employees_divisions foreign key references divisions(division_id),
 resource_id int null
   constraint FK_employees_resources foreign key references resources(resource_id),
 position_id int not null
   constraint FK_employees_positions foreign key references positions(position_id),
 employee_code varchar(30) not null,
 employee_name varchar(150) not null,
 join_date date null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE material_adjustment_reasons(
 adjustment_reason_id int primary key identity(1,1),
 adjustment_type_id int not null
   constraint FK_adj_reasons_adj_types foreign key references material_adjustment_types(adjustment_type_id),
 adjustment_reason_code varchar(30) not null,
 adjustment_reason_name varchar(150) not null,
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE materials(
 material_id int primary key identity(1,1),
 material_code varchar(30) not null,
 material_name varchar(150) not null,
 sku varchar(20) null,
 material_category_id int not null
   constraint FK_materials_categories foreign key references material_categories(material_category_id),
 default_unit_id int not null
   constraint FK_materials_units foreign key references units(unit_id),
 tracking_type varchar(10) not null,        -- LOT / SERIAL / NONE
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 3. ORDER INTAKE ============

CREATE TABLE projects(
 project_id int primary key identity(1,1),
 customer_id int not null
   constraint FK_projects_buyers foreign key references buyers(buyer_id),
 project_md int null
   constraint FK_projects_md foreign key references employees(employee_id),
 project_pic int null
   constraint FK_projects_pic foreign key references employees(employee_id),
 project_name varchar(150) not null,
 no_po varchar(50) null,
 order_date date null,
 [start_date] date null,
 deadline date null,
 delivery_date date null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE size_packs(
 size_pack_id int primary key identity(1,1),
 buyer_id int null
   constraint FK_size_packs_buyers foreign key references buyers(buyer_id),
 size_pack_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE size_pack_details(
 size_pack_detail_id int primary key identity(1,1),
 size_pack_id int not null
   constraint FK_spd_size_packs foreign key references size_packs(size_pack_id),
 size_name varchar(50) not null,
 sort_order int not null default 0,
 [description] varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE articles(
 article_id int primary key identity(1,1),
 project_id int not null
   constraint FK_articles_projects foreign key references projects(project_id),
 size_pack_id int not null
   constraint FK_articles_size_packs foreign key references size_packs(size_pack_id),
 article_name varchar(150) not null,
 style varchar(100) null,
 color varchar(100) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE article_sizes(
 article_size_id int primary key identity(1,1),
 article_id int not null
   constraint FK_article_sizes_articles foreign key references articles(article_id),
 size_pack_detail_id int not null
   constraint FK_article_sizes_spd foreign key references size_pack_details(size_pack_detail_id),
 qty int not null default 0,
 bundle_qty int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE project_attachments(
 project_attachment_id int primary key identity(1,1),
 project_id int not null
   constraint FK_project_attachments_projects foreign key references projects(project_id),
 file_name varchar(255) not null,
 file_path varchar(500) not null,
 file_size_kb int not null,
 file_type varchar(10) not null,            -- jpg/png/pdf/xlsx
 [description] varchar(255) null,           -- "Size chart", "Detail bordir", dll
 sort_order int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE article_photos(
 article_photo_id int primary key identity(1,1),
 article_id int not null
   constraint FK_article_photos_articles foreign key references articles(article_id),
 file_name varchar(255) not null,
 file_path varchar(500) not null,
 file_size_kb int not null,
 sort_order int not null default 0,
 is_primary bit not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 4. WORKFLOW ============

CREATE TABLE workflow_templates(
 workflow_template_id int primary key identity(1,1),
 workflow_code varchar(30) not null,
 workflow_name varchar(150) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE workflow_template_steps(
 step_id int primary key identity(1,1),
 workflow_template_id int not null
   constraint FK_wts_workflow_templates foreign key references workflow_templates(workflow_template_id),
 step_name varchar(150) not null,
 division_id int not null
   constraint FK_wts_divisions foreign key references divisions(division_id),
 sort_order int not null default 0,
 requires_bundle bit not null default 1,     -- 0 = step boleh log tanpa bundle (mis. Cutting)
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Salinan step per artikel. Referensi template hanya untuk info asal;
-- perubahan template tidak mempengaruhi artikel yang sudah dibuat.
CREATE TABLE article_workflows(
 article_workflow_id int primary key identity(1,1),
 article_id int not null
   constraint FK_aw_articles foreign key references articles(article_id),
 workflow_template_id int null
   constraint FK_aw_workflow_templates foreign key references workflow_templates(workflow_template_id),
 step_name varchar(150) not null,
 division_id int not null
   constraint FK_aw_divisions foreign key references divisions(division_id),
 sort_order int not null default 0,
 requires_bundle bit not null default 1,     -- salinan dari template step
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 5. PRODUKSI ============

CREATE TABLE bundles(
 bundle_id int primary key identity(1,1),
 article_id int not null
   constraint FK_bundles_articles foreign key references articles(article_id),
 article_size_id int not null
   constraint FK_bundles_article_sizes foreign key references article_sizes(article_size_id),
 serial varchar(20) not null,
 bundle_no int not null,    -- nomor urut per project, generate di sp_Bundle_Manage, tidak dipakai ulang
 qty int not null default 0,
 sort_order int not null default 0,
 resource_id int null
   constraint FK_bundles_resources foreign key references resources(resource_id),
 resource_person_name varchar(150) null,    -- nama penjahit
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- LOG MURNI, MODEL 1-BARIS-PER-SERAH-TERIMA (Prompt 12b): tidak boleh di-update
-- kecuali trio received_* lewat action RECEIVE. Salah input = soft delete (hanya
-- supervisor/admin) + input baris baru. delete_reason wajib diisi saat delete.
-- INSERT = pekerjaan step selesai (dulu berstatus 'COMPLETED'). Penerimaan oleh divisi
-- tujuan mengisi received_at/received_by_resource_id/received_remark pada baris yang
-- SAMA (dulu baris terpisah berstatus 'RECEIVED') -- status kini selalu diturunkan dari
-- ada/tidaknya received_at, tidak ada kolom status.
-- bundle_id NULL untuk step requires_bundle = 0 (mis. Cutting) -- baris ini bebas
-- berulang, tidak pernah jadi prasyarat step ber-bundle mana pun; article_size_id wajib
-- diisi untuk baris ini (input qty per ukuran). Untuk step requires_bundle = 1, bundle_id
-- wajib diisi (article_size_id NULL, size sudah melekat di bundle) dan maksimal satu
-- baris hidup per (step, bundle). Validasi lengkap di sp_WorkflowLog_Manage.
CREATE TABLE article_workflow_logs(
 workflow_log_id int primary key identity(1,1),
 article_workflow_id int not null
   constraint FK_awl_article_workflows foreign key references article_workflows(article_workflow_id),
 bundle_id int null                          -- NULL = log level artikel (step pra-bundle, mis. Cutting)
   constraint FK_awl_bundles foreign key references bundles(bundle_id),
 article_size_id int null                    -- diisi untuk baris non-bundle (input size manual)
   constraint FK_awl_article_sizes foreign key references article_sizes(article_size_id),
 division_id int not null
   constraint FK_awl_divisions foreign key references divisions(division_id),
 resource_id int null
   constraint FK_awl_resources foreign key references resources(resource_id),
 employee_id int null
   constraint FK_awl_employees foreign key references employees(employee_id),
 qty_ok int not null default 0,
 qty_reject_print int not null default 0,   -- reject sablon
 qty_reject_fabric int not null default 0,  -- reject bahan
 qty_reject_sewing int not null default 0,  -- reject jahit
 qty_rework int not null default 0,
 remark varchar(500) null,
 received_at datetime2 null,
 received_by_resource_id int null           -- sebelumnya received_by, dipertegas ini FK ke resources
   constraint FK_awl_received_by foreign key references resources(resource_id),
 received_remark varchar(500) null,
 target_division_id int null                -- sebelumnya target_division, disamakan pola _id
   constraint FK_awl_target_division foreign key references divisions(division_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null
);

-- Antrian cetak label QR. Dibuat otomatis saat bundle dibuat (job_type BUNDLE_LABEL,
-- ref_id = bundle_id) atau lewat cetak ulang. Pencetakan fisik (Windows service,
-- perakitan TSPL dari payload) dikerjakan di Prompt 11 -- di sini hanya antrian.
CREATE TABLE print_jobs(
 print_job_id int primary key identity(1,1),
 job_type varchar(30) not null,             -- 'BUNDLE_LABEL' (nanti: 'MATERIAL_LABEL')
 ref_id int not null,                       -- bundle_id untuk BUNDLE_LABEL
 payload nvarchar(max) not null,            -- JSON data label; TSPL dirakit oleh print service
 [status] varchar(20) not null default 'PENDING',  -- PENDING/PRINTING/DONE/ERROR
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

-- ============ 6. COSTING ============

CREATE TABLE cost_transactions(
 cost_transaction_id int primary key identity(1,1),
 cost_component_id int not null
   constraint FK_ct_cost_components foreign key references cost_components(cost_component_id),
 project_id int not null
   constraint FK_ct_projects foreign key references projects(project_id),
 origin_entity varchar(50) null,            -- nama tabel sumber (polymorphic)
 origin_id int null,
 amount decimal(19,4) not null default 0,   -- money -> decimal, aman dari pembulatan
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 7. MATERIAL ============

CREATE TABLE material_receipts (
 receipt_id int primary key identity(1,1),
 receipt_no varchar(30) not null,
 receipt_type varchar(30) not null,
 supplier_id int null
   constraint FK_receipts_suppliers foreign key references suppliers(supplier_id),
 received_at datetime2 null,
 remarks nvarchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE material_receipt_items(
 receipt_item_id int primary key identity(1,1),
 receipt_id int not null
   constraint FK_receipt_items_receipts foreign key references material_receipts(receipt_id),
 material_id int not null
   constraint FK_receipt_items_materials foreign key references materials(material_id),
 lot varchar(50) null,
 qty_bruto decimal(18,4) not null default 0,
 qty_netto decimal(18,4) not null default 0,
 unit_id int not null
   constraint FK_receipt_items_units foreign key references units(unit_id),
 unit_price decimal(19,4) not null default 0,
 remarks nvarchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- current_qty DIHAPUS: stok terkini dihitung dari material_movement via view/function
CREATE TABLE material_stocks(
 stock_id int primary key identity(1,1),
 material_id int not null
   constraint FK_stocks_materials foreign key references materials(material_id),
 sku varchar(20) null,
 lot varchar(50) null,
 serial varchar(20) null,
 initial_gross_qty decimal(18,4) not null default 0,
 initial_net_qty decimal(18,4) not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- LOG MURNI: aturan sama dengan article_workflow_logs
CREATE TABLE material_movement(
 movement_id int primary key identity(1,1),
 stock_id int not null
   constraint FK_movement_stocks foreign key references material_stocks(stock_id),
 movement_type_id int not null
   constraint FK_movement_types foreign key references material_movement_types(movement_type_id),
 origin_entity varchar(50) null,
 origin_id int null,
 movement_date date not null,
 qty decimal(18,4) not null,
 giver_employee_id int null
   constraint FK_movement_giver foreign key references employees(employee_id),
 received_employee_id int null
   constraint FK_movement_received_emp foreign key references employees(employee_id),
 received_resource_id int null
   constraint FK_movement_received_res foreign key references resources(resource_id),
 received_person_name varchar(150) null,    -- sebelumnya received_by (varchar), dipertegas ini nama orang
 remarks varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null
);

-- ============ 8. ADJUSTMENT ============

CREATE TABLE material_adjustments(
 adjustment_id int primary key identity(1,1),
 adjustment_no varchar(50) not null,        -- no dokumen
 adjustment_type_id int not null
   constraint FK_adjustments_types foreign key references material_adjustment_types(adjustment_type_id),
 adjustment_date datetime2 not null,
 [status] varchar(20) not null,             -- DRAFT / APPROVED / CANCELLED
 remarks varchar(500) null,
 approved_at datetime2 null,
 approved_by int null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE material_adjustment_details(
 adjustment_detail_id int primary key identity(1,1),
 adjustment_id int not null
   constraint FK_adj_details_adjustments foreign key references material_adjustments(adjustment_id),
 stock_id int not null
   constraint FK_adj_details_stocks foreign key references material_stocks(stock_id),
 lot varchar(50) null,
 unit_id int not null
   constraint FK_adj_details_units foreign key references units(unit_id),
 system_qty decimal(18,4) not null,
 actual_qty decimal(18,4) not null,
 difference_qty as (actual_qty - system_qty) persisted,
 adjustment_reason_id int null
   constraint FK_adj_details_reasons foreign key references material_adjustment_reasons(adjustment_reason_id),
 remarks varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- ============ 9. STASIUN ============
-- Perangkat di lantai produksi yang mencatat log workflow tanpa login user
-- (autentikasi via station_token per perangkat, lihat sp_Station_GetByToken).

CREATE TABLE stations(
 station_id int primary key identity(1,1),
 station_code varchar(30) not null,
 station_name varchar(150) not null,
 division_id int not null
   constraint FK_stations_divisions foreign key references divisions(division_id),
 station_token varchar(64) not null,        -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 10. UNIQUE INDEX (filtered: berlaku hanya untuk baris hidup) ============
-- Dengan pola ini, kode lama bisa dipakai lagi setelah barisnya di-soft-delete.

CREATE UNIQUE INDEX UX_buyers_code            ON buyers(buyer_code)                 WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_divisions_code         ON divisions(division_code)           WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_resource_types_code    ON resource_types(resource_type_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_suppliers_code         ON suppliers(supplier_code)           WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_material_cat_code      ON material_categories(category_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_cost_components_code   ON cost_components(cost_component_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_movement_types_code    ON material_movement_types(movement_type_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_adj_types_code         ON material_adjustment_types(adjustment_type_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_adj_reasons_code       ON material_adjustment_reasons(adjustment_reason_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_employees_code         ON employees(employee_code)           WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_materials_code         ON materials(material_code)           WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_materials_sku          ON materials(sku)                     WHERE deleted_at IS NULL AND sku IS NOT NULL;
CREATE UNIQUE INDEX UX_workflow_templates_code ON workflow_templates(workflow_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_bundles_serial         ON bundles(serial)                    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_receipts_no            ON material_receipts(receipt_no)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stocks_serial          ON material_stocks(serial)            WHERE deleted_at IS NULL AND serial IS NOT NULL;
CREATE UNIQUE INDEX UX_adjustments_no         ON material_adjustments(adjustment_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stations_code          ON stations(station_code)             WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stations_token         ON stations(station_token)            WHERE deleted_at IS NULL;
GO

-- ============ 11. INDEX FK UNTUK PERFORMA QUERY HARIAN ============

CREATE INDEX IX_movement_stock      ON material_movement(stock_id)  WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_bundle          ON article_workflow_logs(bundle_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_article_workflow ON article_workflow_logs(article_workflow_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_bundles_article     ON bundles(article_id);
CREATE INDEX IX_articles_project    ON articles(project_id);
CREATE INDEX IX_stocks_material     ON material_stocks(material_id);
CREATE INDEX IX_stations_division   ON stations(division_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_status   ON print_jobs([status]) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_ref      ON print_jobs(job_type, ref_id) WHERE deleted_at IS NULL;
GO
