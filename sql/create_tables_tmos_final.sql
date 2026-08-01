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

-- Catatan (Prompt 21): tabel Users dan SP SIS_Login/SIS_User_Manage dibuat langsung
-- di database sebelum Fase 0 di atas, jadi tidak ikut di-CREATE lewat file ini (tidak
-- pakai konvensi snake_case/soft-delete di atas). Didokumentasikan di sini sebagai
-- referensi kolom, BUKAN untuk dieksekusi ulang:
--   Users(Id, Username, Password, FullName, Role, IsActive, CreatedAt)
--   Password varchar(500) sejak Prompt 21 -- format simpanan: PBKDF2$<iterasi>$<saltBase64>$<hashBase64>
--   (lihat sql/alter_21_password_pbkdf2.sql, TerakarsaApp.API/Services/PasswordHasher.cs)

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
 show_in_dashboard bit not null default 1,          -- Prompt 36: tampil di dashboard TV atau tidak
 dashboard_mode varchar(20) not null default 'DIVISION',  -- DIVISION | RESOURCE
 dashboard_sort_order int not null default 0,       -- urutan kartu di dashboard
 default_target_per_person int not null default 0,  -- pcs/orang/hari, untuk prefill PPIC
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_divisions_dashboard_mode check (dashboard_mode in ('DIVISION', 'RESOURCE'))
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
 include_in_dashboard bit not null default 1,       -- Prompt 36: ikut dihitung & ditampilkan di dashboard
 counterpart_resource_id int null                   -- Prompt 39/40: resource pasangan di divisi lanjutan (mis.
   constraint FK_resources_counterpart                -- Line A1 di Sewing -> Trim A1 di Buang Benang). Prompt 40:
   foreign key references resources(resource_id),     -- auto-terima WAJIB pakai ini (bukan lagi fallback ke
                                                        -- pengirim) bila valid terhadap divisi tujuan; kalau tidak,
                                                        -- operator wajib pilih penerima manual. Satu arah, opsional.
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
 employee_code varchar(30) null,    -- Prompt 35: boleh kosong -- penjahit yang belum
                                     -- terdaftar kode tapi sudah mulai kerja bisa didaftar
                                     -- dulu, kode diisi menyusul lewat Edit
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

-- Status project (Prompt 18): OTOMATIS (Not Started/On Going) diturunkan di SP select
-- dari ada/tidaknya log workflow hidup -- TIDAK disimpan sebagai data. manual_status hanya
-- terisi untuk status MANUAL (ON_HOLD/COMPLETED/CANCELLED), keputusan bisnis lewat tombol
-- aksi (bukan input teks bebas). manual_status IS NOT NULL mengunci aksi produksi (bundle,
-- log workflow) -- lihat sp_Bundle_Manage.sql / sp_WorkflowLog_Manage.sql.
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
 material_name varchar(150) null,           -- nama bahan / fabric type
 order_date date null,
 [start_date] date null,
 deadline date null,
 delivery_date date null,
 remarks varchar(500) null,                 -- catatan bebas
 is_urgent bit not null default 0,          -- penanda urgent
 manual_status varchar(20) null,            -- NULL = otomatis (Not Started/On Going); ON_HOLD / COMPLETED / CANCELLED
 status_reason varchar(255) null,           -- wajib utk ON_HOLD & CANCELLED (komunikasi lintas divisi)
 status_changed_at datetime2 null,
 status_changed_by int null,
 bundle_letter char(1) null,                -- kode huruf bundle per project (A-Z berputar), generate di SIS_Project_Manage; NULL = project lama tanpa huruf
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

-- Prompt 19: hanya berisi baris untuk size ber-qty order > 0 (dijaga di SIS_Article_Manage,
-- lihat sql/sp_Article_Manage.sql) -- size ber-qty 0 tidak punya baris di sini.
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
 auto_receive bit not null default 0,       -- serah ke step ini otomatis diterima (received_at terisi saat insert log)
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Salinan step per artikel. Referensi template hanya untuk info asal;
-- perubahan template tidak mempengaruhi artikel yang sudah dibuat.
-- Prompt 17: step "Bundling" (is_bundling = 1) adalah step implisit yang disisipkan
-- OTOMATIS oleh sistem (SIS_ArticleWorkflow_Manage APPLY/SAVE) tepat di antara step
-- non-bundle terakhir dan step ber-bundle pertama -- bukan bagian dari template
-- (workflow_template_steps tidak punya kolom ini) dan tidak dikelola user di editor step.
-- Baris log-nya (article_workflow_logs) hanya lahir lewat SIS_Bundle_Manage CREATE (lihat
-- komentar di tabel article_workflow_logs) -- entitas ini menerima hasil cutting (auto-
-- receive log non-bundle pending) dan mencatat pembuatan bundle.
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
 auto_receive bit not null default 0,       -- salinan dari template step; selalu 0 utk step Bundling implisit
 is_bundling bit not null default 0,         -- step Bundling implisit (disisipkan sistem saat APPLY, bukan dari template)
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
 employee_id int null    -- Prompt 32: penjahit dari master employees, menggantikan resource_person_name lama
   constraint FK_bundles_employees foreign key references employees(employee_id),
 remarks varchar(500) null,    -- Prompt 35: dulu resource_person_name (nama penjahit teks bebas,
                                -- DEPRECATED sejak Prompt 32) -- di-rename & direpurpose jadi catatan
                                -- bebas bundle, diisi/diedit langsung lewat BundleManager.razor
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null    -- Prompt 29: alasan hapus lewat SIS_SuperAdmin_Manage BUNDLE_DELETE
);

-- LOG MURNI, MODEL 1-BARIS-PER-SERAH-TERIMA (Prompt 12b): tidak boleh di-update
-- kecuali trio received_* lewat action RECEIVE, atau (Prompt 12d) trio updated_* lewat
-- action UPDATE selama received_at masih NULL. Salah input = soft delete (hanya
-- supervisor/admin) + input baris baru. delete_reason wajib diisi saat delete.
-- Identitas (Prompt 12d): PENCATAT = created_by/updated_by (user login; dari stasiun =
-- user sistem 'station'). PELAKSANA = resource_id/updated_by_resource_id (opsional untuk
-- step non-bundle). Tidak ada kolom employee di log -- karyawan pelaksana didaftarkan
-- sebagai resource (employees.resource_id).
-- INSERT = pekerjaan step selesai (dulu berstatus 'COMPLETED'). Penerimaan oleh divisi
-- tujuan mengisi received_at/received_by_resource_id/received_remark pada baris yang
-- SAMA (dulu baris terpisah berstatus 'RECEIVED') -- status kini selalu diturunkan dari
-- ada/tidaknya received_at, tidak ada kolom status.
-- bundle_id NULL untuk step requires_bundle = 0 (mis. Cutting) -- baris ini bebas
-- berulang, tidak pernah jadi prasyarat step ber-bundle mana pun; article_size_id wajib
-- diisi untuk baris ini (input qty per ukuran). Untuk step requires_bundle = 1, bundle_id
-- wajib diisi (article_size_id NULL, size sudah melekat di bundle) dan maksimal satu
-- baris hidup per (step, bundle). Validasi lengkap di sp_WorkflowLog_Manage.
-- Prompt 17: baris untuk step Bundling (article_workflows.is_bundling = 1) TIDAK dibuat
-- lewat @Action = 'CREATE' biasa (ditolak) -- hanya lahir otomatis di SIS_Bundle_Manage
-- CREATE (bundle_id = bundle baru, resource_id = pelaksana bundling opsional, qty_ok = qty
-- bundle, received_at NULL sampai divisi berikutnya RECEIVE). RECEIVE/UNRECEIVE/DELETE baris
-- ini tetap lewat jalur generik di sp_WorkflowLog_Manage; UPDATE praktis hanya lewat
-- SIS_Bundle_Manage UPDATE (sinkron qty_ok/resource_id dengan bundle).
-- Prompt 28: qty_reject_rework/qty_lost -- dua kategori qty tambahan, sama pola dengan
-- qty_reject_*. log_type membedakan baris normal dari baris ADJUSTMENT (mutasi antar
-- kategori qty pada bundle+step yang sama, lihat SIS_WorkflowLog_Manage action ADJUST) --
-- baris ADJUSTMENT boleh berisi nilai NEGATIF pada kolom reject/lost (mutasi), qty_ok pada
-- baris ADJUSTMENT selalu >= 0, dan jumlah keenam kolom qty baris ADJUSTMENT selalu 0.
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
 qty_reject_rework int not null default 0,  -- reject rework (Prompt 28)
 qty_lost int not null default 0,           -- hilang (Prompt 28)
 log_type varchar(15) not null default 'NORMAL',  -- NORMAL / ADJUSTMENT (mutasi antar kategori qty, total 0)
 remark varchar(500) null,
 received_at datetime2 null,
 received_by_resource_id int null           -- sebelumnya received_by, dipertegas ini FK ke resources
   constraint FK_awl_received_by foreign key references resources(resource_id),
 received_remark varchar(500) null,
 target_division_id int null                -- sebelumnya target_division, disamakan pola _id
   constraint FK_awl_target_division foreign key references divisions(division_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,                   -- PENCATAT: user login (dari stasiun = user sistem 'station')
 updated_at datetime2 null,                 -- Prompt 12d: trio ini hanya diisi action UPDATE (revisi
 updated_by int null,                       -- sebelum diterima); baris terkunci begitu received_at terisi
 updated_by_resource_id int null            -- operator sesi aktif saat revisi dari stasiun, opsional
   constraint FK_awl_updated_by_resource foreign key references resources(resource_id),
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
 default_resource_id int null               -- Prompt 16: 1 device = 1 resource (opsional)
   constraint FK_stations_default_resource foreign key references resources(resource_id),
 allow_resource_change bit not null default 1, -- 0 = terkunci ke default_resource_id
 pairing_code varchar(10) null,             -- Prompt 20: kode pairing aktif; NULL = tidak ada
 pairing_code_expires_at datetime2 null,
 paired_at datetime2 null,                  -- kapan terakhir perangkat berhasil klaim
 enable_packing bit not null default 0,     -- Prompt 25: stasiun ini boleh membuka modul packing
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 9b. PACKING ============
-- Karung (pack) berisi campuran artikel/size dalam SATU project, dibuat di stasiun khusus
-- packing dari stok hasil step TERAKHIR workflow tiap artikel. Stok tersedia dihitung dari
-- article_workflow_logs + pack_items (TIDAK ada tabel stok/saldo terpisah), lihat
-- sp_Pack_Select.sql (SIS_Pack_StockAvailable).

CREATE TABLE packs(
 pack_id int primary key identity(1,1),
 project_id int not null
   constraint FK_packs_projects foreign key references projects(project_id),
 pack_no int not null,                      -- urut per project, generate di sp_Pack_Manage, tidak dipakai ulang
 serial varchar(20) not null,               -- PK{yy}-{6 digit global}
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null
);

CREATE TABLE pack_items(
 pack_item_id int primary key identity(1,1),
 pack_id int not null
   constraint FK_pack_items_packs foreign key references packs(pack_id),
 article_id int not null
   constraint FK_pack_items_articles foreign key references articles(article_id),
 article_size_id int not null
   constraint FK_pack_items_sizes foreign key references article_sizes(article_size_id),
 qty_plan int not null,
 qty_actual int null,                       -- NULL = belum dikonfirmasi (dua lapis qty, lihat CLAUDE.md)
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 9c. JAM KERJA & TARGET DEFAULT ============
-- Prompt 36: fondasi dashboard target harian. Nilai di sini HANYA dipakai untuk prefill
-- form Planning Harian PPIC (Prompt 37) dan fallback tampilan bila PPIC belum input --
-- dashboard TV (Prompt 38) selalu memakai angka yang sudah di-save PPIC.

CREATE TABLE work_schedule_defaults(
 work_schedule_default_id int primary key identity(1,1),
 division_id int not null
   constraint FK_wsd_divisions foreign key references divisions(division_id),
 day_of_week tinyint not null,              -- 1 = Senin ... 7 = Minggu
 is_working_day bit not null default 1,     -- 0 = libur default (mis. Minggu)
 start_time time(0) not null,
 end_time time(0) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_wsd_day_of_week check (day_of_week between 1 and 7)
);

CREATE TABLE work_break_defaults(
 work_break_default_id int primary key identity(1,1),
 break_name varchar(150) not null,          -- mis. 'Istirahat Siang'
 day_of_week tinyint null,                  -- NULL = berlaku semua hari
 start_time time(0) not null,
 end_time time(0) not null,
 sort_order int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_wbd_day_of_week check (day_of_week is null or day_of_week between 1 and 7)
);
GO

-- ============ 9d. PLANNING HARIAN PPIC ============
-- Prompt 37: rencana kerja harian per divisi (+ per resource bila dashboard_mode =
-- RESOURCE), dasar dashboard target TV (Prompt 38). Setting default (9c) hanya prefill --
-- baris di sini adalah satu-satunya data yang dianggap "sudah direncanakan".

CREATE TABLE daily_division_plans(
 daily_division_plan_id int primary key identity(1,1),
 plan_date date not null,
 division_id int not null
   constraint FK_ddp_divisions foreign key references divisions(division_id),
 is_holiday bit not null default 0,         -- 1 = divisi libur pada tanggal ini
 start_time time(0) null,                   -- NULL bila libur
 end_time time(0) null,
 headcount int null,                        -- dipakai bila dashboard_mode = DIVISION
 target_per_person int null,                -- dipakai bila dashboard_mode = DIVISION
 remark varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

CREATE TABLE daily_resource_plans(
 daily_resource_plan_id int primary key identity(1,1),
 daily_division_plan_id int not null
   constraint FK_drp_daily_division_plans foreign key references daily_division_plans(daily_division_plan_id),
 resource_id int not null
   constraint FK_drp_resources foreign key references resources(resource_id),
 headcount int not null default 0,
 target_per_person int not null default 0,
 start_time time(0) null,                   -- override; NULL = ikut jam divisi
 end_time time(0) null,                     -- override; NULL = ikut jam divisi
 remark varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 9e. DASHBOARD TARGET HARIAN (TOKEN KIOSK) ============
-- Prompt 38: token akses layar TV lantai produksi (read-only, tanpa login). Berbeda dari
-- stations -- tabel ini TIDAK terikat divisi, boleh ada banyak token aktif bersamaan.

CREATE TABLE dashboard_tokens(
 dashboard_token_id int primary key identity(1,1),
 token_name varchar(150) not null,          -- mis. 'TV Line Jahit 1'
 dashboard_token varchar(64) not null,      -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 refresh_interval_minutes int not null default 30,  -- harus habis membagi 60

 last_seen_at datetime2 null,               -- diperbarui saat token dipakai
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_dashboard_tokens_refresh_interval check (refresh_interval_minutes in (5, 10, 15, 20, 30, 60))
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
CREATE UNIQUE INDEX UX_employees_code         ON employees(employee_code)           WHERE deleted_at IS NULL AND employee_code IS NOT NULL;
CREATE UNIQUE INDEX UX_materials_code         ON materials(material_code)           WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_materials_sku          ON materials(sku)                     WHERE deleted_at IS NULL AND sku IS NOT NULL;
CREATE UNIQUE INDEX UX_workflow_templates_code ON workflow_templates(workflow_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_bundles_serial         ON bundles(serial)                    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_receipts_no            ON material_receipts(receipt_no)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stocks_serial          ON material_stocks(serial)            WHERE deleted_at IS NULL AND serial IS NOT NULL;
CREATE UNIQUE INDEX UX_adjustments_no         ON material_adjustments(adjustment_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stations_code          ON stations(station_code)             WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stations_token         ON stations(station_token)            WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_stations_pairing_code  ON stations(pairing_code)             WHERE pairing_code IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX UX_packs_serial           ON packs(serial)                      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_wsd_division_day       ON work_schedule_defaults(division_id, day_of_week) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_ddp_date_division       ON daily_division_plans(plan_date, division_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_drp_plan_resource       ON daily_resource_plans(daily_division_plan_id, resource_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_dashboard_tokens_token  ON dashboard_tokens(dashboard_token) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_dashboard_tokens_name   ON dashboard_tokens(token_name) WHERE deleted_at IS NULL;
GO

-- ============ 11. INDEX FK UNTUK PERFORMA QUERY HARIAN ============

CREATE INDEX IX_ddp_plan_date       ON daily_division_plans(plan_date) WHERE deleted_at IS NULL;
CREATE INDEX IX_movement_stock      ON material_movement(stock_id)  WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_bundle          ON article_workflow_logs(bundle_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_article_workflow ON article_workflow_logs(article_workflow_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_bundles_article     ON bundles(article_id);
CREATE INDEX IX_articles_project    ON articles(project_id);
CREATE INDEX IX_stocks_material     ON material_stocks(material_id);
CREATE INDEX IX_stations_division   ON stations(division_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_status   ON print_jobs([status]) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_ref      ON print_jobs(job_type, ref_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_packs_project       ON packs(project_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_pack_items_pack     ON pack_items(pack_id) WHERE deleted_at IS NULL;
GO
