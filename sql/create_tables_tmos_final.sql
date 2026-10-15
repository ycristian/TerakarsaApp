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
--   Users(Id, Username, Password, FullName, Role, IsActive, CreatedAt, home_route)
--   Password varchar(500) sejak Prompt 21 -- format simpanan: PBKDF2$<iterasi>$<saltBase64>$<hashBase64>
--   (lihat sql/alter_21_password_pbkdf2.sql, TerakarsaApp.API/Services/PasswordHasher.cs)
--   home_route varchar(100) null sejak Prompt 71 -- halaman awal setelah login
--   (role baru WAREHOUSE / "Admin Gudang" -> /gudang/benang). Lihat
--   sql/inv/alter_71_home_route.sql; nilainya dibawa claim JWT "home_route".

-- Catatan schema lain (file ini HANYA canonical untuk schema dbo):
--   schema `tni` (module PDH TNI AD, Prompt 60-69)  -> sql/tni/create_schema_tni.sql
--   schema `inv` (module Stok Benang, Prompt 71-77) -> sql/inv/create_71_inv_thread.sql
--     + sql/inv/create_74_inv_thread_opname.sql (tabel stock opname)
-- Keduanya hanya MEMBACA tabel dbo (projects, resources, users) dan menyentuh dbo
-- sebatas seed Modules/UserModules + kolom Users.home_route di atas.

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
 ppic_managed bit not null default 0,                -- Prompt 53: divisi ini boleh dikelola lewat module PPIC_EMPLOYEE
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
 is_gate_operator bit not null default 0,   -- Prompt 70: jabatan ini boleh membuka menu satpam
                                            -- di aplikasi gate. Akses melekat pada JABATAN,
                                            -- bukan pada kartu dan bukan pada user login
                                            -- (aplikasi gate memang tanpa login).
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
 color_hex varchar(7) null,                         -- Prompt 70: warna holder/lanyard fisik line ini
                                                    -- (mis. '#1E5FA8'), dipakai badge warna di layar
                                                    -- gate supaya satpam bisa mencocokkan dengan holder
                                                    -- yang dipakai karyawan. NULL = warna netral.
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
 is_active bit not null default 1,  -- Prompt 53: nonaktif = hilang dari dropdown employee, data lama (log/bundle/project) tetap utuh
 phone_no varchar(20) null,         -- Prompt 58: HANYA digit (normalisasi di SP: buang non-digit,
                                    -- awalan 62 -> 0). Dipakai station sebagai penanda "orang yang
                                    -- sama" saat menawarkan "Aktifkan lagi?"
 inactive_date date null,           -- Prompt 58: tanggal terakhir kerja, diisi saat dinonaktifkan
 inactive_reason varchar(20) null,  -- Prompt 58: RESIGN / HABIS_KONTRAK / DIBERHENTIKAN / PINDAH_DIVISI
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
 print_kupon bit not null default 0,        -- Prompt 41: cetak kupon borongan saat baris step ini diterima (hanya valid requires_bundle = 1)
 unit_price decimal(19,4) not null default 0,  -- Prompt 59: harga ARAHAN per pcs; disalin ke article_workflows saat APPLY.
                                                -- Perubahan di sini TIDAK merambat ke artikel yang sudah ada.
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
 print_kupon bit not null default 0,        -- Prompt 41: salinan dari template step; selalu 0 utk step Bundling implisit
 unit_price decimal(19,4) not null default 0,  -- Prompt 59: harga per pcs yang BERLAKU untuk artikel ini (dasar upah di
                                                -- Rekap Produksi stasiun). Disalin dari template saat APPLY, lalu bebas
                                                -- diubah per artikel lewat SAVE -- tidak pernah di-snapshot ke log.
                                                -- Step Bundling implisit selalu 0.
 is_bundling bit not null default 0,         -- step Bundling implisit (disisipkan sistem saat APPLY, bukan dari template)
 inactive_at datetime2 null,    -- Prompt 50: diisi = step berhenti jadi jalur untuk unit baru
                                 -- (restrukturisasi setelah ada log). Baris tetap deleted_at
                                 -- IS NULL dengan sengaja -- lihat sp_ArticleWorkflow_Restructure.sql.
 inactive_by int null,
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
 target_division_id_original int null,      -- Prompt 50: nilai target_division_id SEBELUM
                                              -- redirect pertama (restrukturisasi workflow) --
                                              -- hanya diisi kalau masih NULL, redirect kedua
                                              -- tidak menimpanya. Lihat sp_ArticleWorkflow_Restructure.sql.
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,                   -- PENCATAT: user login (dari stasiun = user sistem 'station')
 updated_at datetime2 null,                 -- Prompt 12d: trio ini hanya diisi action UPDATE (revisi
 updated_by int null,                       -- sebelum diterima); baris terkunci begitu received_at terisi
 updated_by_resource_id int null            -- operator sesi aktif saat revisi dari stasiun, opsional
   constraint FK_awl_updated_by_resource foreign key references resources(resource_id),
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null,
 lock_id int null                           -- Prompt 55: lock yang SEDANG berlaku untuk baris ini.
                                             -- NULL = bebas diubah/dihapus (selama saldo tidak jadi
                                             -- minus). Terisi = beku di SEMUA jalur, termasuk
                                             -- SIS_SuperAdmin_Manage -- pesan 'LOCKED|...'.
                                             -- Periode gajian baris ini = lock_id ->
                                             -- workflow_locks.payroll_period_id (TIDAK ada kolom
                                             -- periode di sini). FK_awl_workflow_locks ditambahkan
                                             -- di bagian 12 (workflow_locks baru dibuat di 9g,
                                             -- setelah tabel ini -- dan workflow_lock_items sendiri
                                             -- menunjuk balik ke sini).
);

-- Prompt 48: daftar printer fisik. Menambah/mengganti printer = INSERT/UPDATE di sini,
-- tidak perlu deploy ulang PrintService.
CREATE TABLE print_devices(
 print_device_id int primary key identity(1,1),
 device_code varchar(30) not null,          -- 'THERMAL', 'LABEL', 'THERMAL_FINISHING', dst
 device_name varchar(150) not null,         -- nama untuk manusia, mis. 'Struk Lantai 1'
 printer_name varchar(255) not null,        -- nama printer Windows PERSIS
 render_mode varchar(20) not null           -- 'TOKEN' (dirender SP) | 'RAW_TSPL' (dirakit C#)
   constraint CK_print_devices_render_mode check (render_mode in ('TOKEN','RAW_TSPL')),
 chars_per_line int not null default 48,    -- lebar font A
 chars_per_line_small int not null default 64, -- lebar font B
 is_active bit not null default 1,
 -- Prompt 77 (sql/inv/alter_77_print_devices_mobile.sql): pencetak bisa berupa HP
 -- Android (printer Bluetooth) selain PC Windows.
 transport varchar(20) not null default 'WINDOWS'   -- WINDOWS | ANDROID_BT
   constraint CK_print_devices_transport check (transport in ('WINDOWS','ANDROID_BT')),
 device_token varchar(64) null,             -- ANDROID_BT saja; header X-Print-Device-Token
 last_seen_at datetime2 null,               -- terakhir HP mengklaim/melapor job
 last_seen_info varchar(200) null,          -- nama printer BT + versi app
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Prompt 48: pemetaan job_type -> printer tujuan.
CREATE TABLE print_job_routes(
 print_job_route_id int primary key identity(1,1),
 job_type varchar(30) not null,
 print_device_id int not null
   constraint FK_pjr_print_devices foreign key references print_devices(print_device_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Ad hoc (2026-09-01): daftar job_type "kupon" (thermal, render_mode TOKEN) yang boleh diklaim
-- TerakarsaApp.PrintService -- dipindah dari array hardcode C# (Worker.cs KuponJobTypes) ke
-- sini supaya job_type struk BARU tidak butuh update/republish/restart service, cukup INSERT
-- baris di sini (lihat sql/adhoc_print_kupon_job_types.sql). Job_type LABEL (render_mode
-- RAW_TSPL, TsplBuilder.cs) TETAP hardcode di Worker.cs, TIDAK disimpan di sini.
CREATE TABLE print_kupon_job_types(
 print_kupon_job_type_id int primary key identity(1,1),
 job_type varchar(30) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
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
 print_device_id int null                   -- Prompt 48: diisi SAAT KLAIM (bukan saat dibuat) --
   constraint FK_print_jobs_print_devices    -- catatan printer mana yang benar-benar dipakai;
   foreign key references print_devices(print_device_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Antrian cetak KHUSUS TESTING (mirror print_jobs persis) -- saat TerakarsaApp.PrintService
-- jalan dengan DryRun=true, worker memanggil varian *_DryRun dari Claim/Report/Dispatch yang
-- baca/tulis ke sini, BUKAN ke print_jobs -- supaya polling/klaim/testing tidak pernah
-- menyentuh antrian cetak live. Diisi lewat SIS_PrintJobDryRun_Seed (copy satu baris dari
-- print_jobs asli, baris sumbernya TIDAK diubah). print_device_id tetap FK ke print_devices
-- yang sama (routing config bukan hal yang perlu dipisah live/dryrun).
CREATE TABLE print_jobs_dryrun(
 print_job_id int primary key identity(1,1),
 job_type varchar(30) not null,
 ref_id int not null,
 payload nvarchar(max) not null,
 [status] varchar(20) not null default 'PENDING',
 error_message varchar(500) null,
 retry_count int not null default 0,
 printed_at datetime2 null,
 print_device_id int null
   constraint FK_print_jobs_dryrun_print_devices foreign key references print_devices(print_device_id),
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

-- ============ 9f. APP SETTINGS ============
-- Saklar konfigurasi global tingkat sistem. Baris tunggal (id = 1), kolom bit per setting --
-- bukan key-value, karena baru satu setting yang dibutuhkan (auto_print_coupon_active,
-- saklar master auto-print kupon borongan Prompt 41, terpisah dari flag print_kupon per step).

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
GO

-- ============ 9g. LOCK LOG WORKFLOW & PERIODE GAJIAN ============
-- Prompt 55: baris article_workflow_logs yang belum di-lock boleh diubah/dihapus kapan pun
-- (asal saldo tidak jadi minus); yang sudah di-lock beku di semua jalur (termasuk Super Admin).
-- Pelepasan lock HANYA lewat unlock_requests yang disetujui admin. Tidak ada kolom status di
-- keempat tabel ini -- keadaan diturunkan dari timestamp (finalized_at, released_at,
-- approved_at/rejected_at, deleted_at).

-- Periode gajian: rumus Sabtu 10:00 Prompt 30, sekarang jadi baris bernomor. Periode ke-N
-- tahun Y BERAKHIR di Sabtu ke-N tahun itu jam 10:00, period_start = period_end - 7 hari.
-- Diisi lewat SIS_PayrollPeriod_Manage GENERATE_YEAR (sql/sp_PayrollPeriod_Manage.sql).
CREATE TABLE payroll_periods(
 payroll_period_id int primary key identity(1,1),
 period_year smallint not null,
 period_no tinyint not null,                -- 1..52/53 (jumlah Sabtu di tahun itu)
 period_code varchar(10) not null,          -- 'YY-wNN', mis. '26-w40' -- nomor periode internal, bukan ISO week
 period_start datetime2 not null,           -- inklusif
 period_end datetime2 not null,             -- eksklusif
 finalized_at datetime2 null,               -- disiapkan, UI finalisasi menyusul
 finalized_by int null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Header satu kali tekan Lock di stasiun (atau lock sistem dari golive_55_lock_existing.sql).
CREATE TABLE workflow_locks(
 lock_id int primary key identity(1,1),
 division_id int not null                   -- divisi pemilik baris OUT yang di-lock
   constraint FK_wl_divisions foreign key references divisions(division_id),
 station_id int null                        -- NULL untuk lock sistem (go-live)
   constraint FK_wl_stations foreign key references stations(station_id),
 payroll_period_id int not null             -- dipilih PIC saat menekan Lock
   constraint FK_wl_payroll_periods foreign key references payroll_periods(payroll_period_id),
 locked_by_resource_id int null             -- operator sesi stasiun
   constraint FK_wl_resources foreign key references resources(resource_id),
 locked_by_name varchar(150) null,          -- hanya lock sistem ('SYSTEM - GO LIVE');
                                             -- nanti dipakai identitas kartu NFC
 locked_at datetime2 not null default sysdatetime(),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Pengajuan buka lock dari stasiun. Menunggu = approved_at IS NULL AND rejected_at IS NULL
-- AND deleted_at IS NULL; pembatalan oleh pengaju = soft delete.
CREATE TABLE unlock_requests(
 request_id int primary key identity(1,1),
 division_id int not null
   constraint FK_ur_divisions foreign key references divisions(division_id),
 station_id int null
   constraint FK_ur_stations foreign key references stations(station_id),
 reason varchar(500) not null,              -- wajib, minimal 5 karakter
 requested_by_resource_id int null          -- operator sesi stasiun
   constraint FK_ur_resources foreign key references resources(resource_id),
 approved_at datetime2 null,
 approved_by int null,
 rejected_at datetime2 null,
 rejected_by int null,
 admin_note varchar(500) null,              -- wajib saat REJECT
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Isi lock + riwayat. Lock yang dilepas TIDAK dihapus (released_at terisi) supaya jejak
-- "baris ini pernah di-lock ke periode mana, dibuka oleh request mana" tetap utuh.
CREATE TABLE workflow_lock_items(
 lock_item_id int primary key identity(1,1),
 lock_id int not null
   constraint FK_wli_workflow_locks foreign key references workflow_locks(lock_id),
 workflow_log_id int not null
   constraint FK_wli_article_workflow_logs foreign key references article_workflow_logs(workflow_log_id),
 -- Snapshot nilai baris saat di-lock (bukti isi periode gajian tidak berubah diam-diam).
 snap_qty_ok int not null default 0,
 snap_qty_reject_print int not null default 0,
 snap_qty_reject_fabric int not null default 0,
 snap_qty_reject_sewing int not null default 0,
 snap_qty_reject_rework int not null default 0,
 snap_qty_lost int not null default 0,
 snap_article_size_id int null,
 snap_resource_id int null,
 snap_target_division_id int null,
 released_at datetime2 null,                -- terisi saat lock dilepas oleh request yang disetujui
 released_by_request_id int null
   constraint FK_wli_unlock_requests foreign key references unlock_requests(request_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);

-- Detail pengajuan. Tanpa updated_*/deleted_* -- ikut nasib header.
CREATE TABLE unlock_request_items(
 request_item_id int primary key identity(1,1),
 request_id int not null
   constraint FK_uri_unlock_requests foreign key references unlock_requests(request_id),
 workflow_log_id int not null
   constraint FK_uri_article_workflow_logs foreign key references article_workflow_logs(workflow_log_id),
 lock_item_id int not null                  -- lock aktif yang diminta dilepas
   constraint FK_uri_workflow_lock_items foreign key references workflow_lock_items(lock_item_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null
);
GO

-- ============ 9h. ABSENSI PEGAWAI (Prompt 58) ============
-- Absen harian diisi MANUAL oleh PIC line lewat perangkat stasiun (belum ada RFID).
-- Nanti data RFID mengisi tabel yang sama dengan source = 'RFID', PIC tinggal mengoreksi.
-- Telat TIDAK disimpan -- dihitung saat dibaca dari work_schedule_defaults divisi station.

CREATE TABLE employee_attendances(
 attendance_id int primary key identity(1,1),
 employee_id int not null
   constraint FK_ea_employees foreign key references employees(employee_id),
 attendance_date date not null,
 resource_id int not null                   -- line tempat absen DICATAT (bukan line pegawai saat ini)
   constraint FK_ea_resources foreign key references resources(resource_id),
 status char(1) not null                    -- H Hadir, I Izin, S Sakit, A Alpa, C Cuti
   constraint CK_ea_status check (status IN ('H','I','S','A','C')),
 check_in time(0) null,                     -- hanya boleh terisi kalau status = 'H'
 check_out time(0) null,                    -- boleh lebih kecil dari check_in (lewat tengah malam)
 note varchar(200) null,                    -- keterangan, mis. 'Surat dokter'
 source varchar(10) not null
   constraint DF_ea_source default 'MANUAL', -- MANUAL / RFID (RFID belum dipakai)
 station_id int null                        -- station yang TERAKHIR menyimpan
   constraint FK_ea_stations foreign key references stations(station_id),
 recorded_by_resource_id int not null       -- operator sesi saat pertama diisi
   constraint FK_ea_recorded_resource foreign key references resources(resource_id),
 updated_by_resource_id int null            -- operator sesi saat terakhir diubah
   constraint FK_ea_updated_resource foreign key references resources(resource_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,                   -- user sistem station_system
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_ea_time_only_hadir check (status = 'H' OR (check_in IS NULL AND check_out IS NULL))
);
GO


-- ============ 9i. JABATAN PER DIVISI (Prompt 58 lanjutan) ============
-- Pembatas pilihan jabatan saat mendaftar pegawai (mis. divisi Sew + QC hanya menawarkan
-- Penjahit/Helper/QC). Many-to-many: satu jabatan dipakai beberapa divisi, dan positions yang
-- sudah ada memang dipakai lintas divisi oleh employees.
-- Diatur dari halaman Master Jabatan. Divisi TANPA satu pun baris di sini dianggap "belum
-- diatur" dan tetap menawarkan SEMUA jabatan -- lihat SIS_Position_GetByDivision.

CREATE TABLE division_positions(
 division_position_id int primary key identity(1,1),
 division_id int not null
   constraint FK_divpos_divisions foreign key references divisions(division_id),
 position_id int not null
   constraint FK_divpos_positions foreign key references positions(position_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 9j. OUTPUT NON-PO (Prompt 59) ============
-- Pekerjaan di luar PO/bundle yang diinput PIC dari stasiun (sampel, order toko tanpa PO,
-- dsb). MASUK UPAH resource, jadi punya periode gajian sendiri -- tapi TIDAK ikut mekanisme
-- lock Prompt 55: edit/hapus bebas selama periodenya belum finalized_at.
-- payroll_period_id DISIMPAN (bukan dihitung ulang saat baca) supaya rekap periode cukup
-- satu join; SP menghitungnya ulang dari output_at setiap CREATE/UPDATE.
-- Tidak ada kolom "jenis" -- keterangan bebas sudah cukup (keputusan prompt).

CREATE TABLE non_po_outputs(
 non_po_output_id int primary key identity(1,1),
 resource_id int not null                  -- resource sesi stasiun (pemilik upah)
   constraint FK_npo_resources foreign key references resources(resource_id),
 division_id int not null                  -- divisi resource, disalin SP (bukan dari client)
   constraint FK_npo_divisions foreign key references divisions(division_id),
 payroll_period_id int not null            -- dihitung SP dari output_at (cut-off Sabtu 10:00)
   constraint FK_npo_payroll_periods foreign key references payroll_periods(payroll_period_id),
 output_at datetime2 not null,             -- tanggal + jam pekerjaan; penentu periode
 qty int not null,                         -- > 0 (ditegakkan SIS_NonPoOutput_Manage)
 unit_price decimal(19,4) not null,        -- >= 0 (ditegakkan SIS_NonPoOutput_Manage)
 remark nvarchar(500) not null,            -- wajib diisi
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,                  -- user sistem station_system
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 9k. ABSENSI RFID (Prompt 70) ============
-- Kartu RFID TIDAK dibawa pulang: dititip di rak gate, diambil pagi, dikembalikan sore. Karena
-- itu status kartu = status orang, dan absensi diturunkan dari tap ambil/kembali kartu -- tanpa
-- tombol MASUK/PULANG. Seluruh keputusan in/out ada di SIS_Gate_Tap (sql/sp_Gate.sql).
-- Hanya UID kartu yang dipakai; TIDAK ADA data yang ditulis ke kartu.
--
-- CATATAN: no. telp karyawan yang dikumpulkan satpam di gate masuk ke employees.phone_no
-- (kolom Prompt 58), BUKAN kolom baru -- lihat catatan di sql/alter_70_absensi_rfid.sql.

-- Lapis identitas UMUM, bukan tabel milik modul absensi: kartu yang sama nantinya dipakai
-- untuk pengambilan barang di gudang (di luar cakupan Prompt 70).
CREATE TABLE employee_cards(
 employee_card_id int primary key identity(1,1),
 employee_id int not null
   constraint FK_ec_employees foreign key references employees(employee_id),
 card_uid varchar(20) not null,             -- 10 digit desimal, DISIMPAN SUDAH DI-PAD NOL DI DEPAN
 card_type varchar(20) not null             -- TETAP / SEMENTARA
   constraint CK_ec_card_type check (card_type IN ('TETAP','SEMENTARA')),
 card_status varchar(20) not null           -- AKTIF / NONAKTIF
   constraint CK_ec_card_status check (card_status IN ('AKTIF','NONAKTIF')),
 issued_at datetime2 not null
   constraint DF_ec_issued_at default sysdatetime(),
 issued_by_employee_id int null             -- satpam yang mendaftarkan dari gate; NULL kalau
   constraint FK_ec_issued_by_employee     -- didaftarkan dari admin panel (pelakunya sudah
   foreign key references employees(employee_id),   -- tercatat di created_by)
 remarks varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Sesi melekat pada KARYAWAN, bukan pada kartu: beberapa kartu aktif milik satu orang tetap
-- bermuara ke satu sesi.
CREATE TABLE attendance_sessions(
 attendance_session_id int primary key identity(1,1),
 employee_id int not null
   constraint FK_as_employees foreign key references employees(employee_id),
 -- division_id/resource_id di-SNAPSHOT saat check in supaya mutasi line tidak mengubah
 -- riwayat absensi.
 division_id int not null
   constraint FK_as_divisions foreign key references divisions(division_id),
 resource_id int null
   constraint FK_as_resources foreign key references resources(resource_id),
 work_date date not null,                   -- tanggal check in (pemilik sesi)
 check_in_at datetime2 not null,
 check_out_at datetime2 null,               -- NULL = belum / tidak diketahui
 session_status varchar(20) not null        -- OPEN / CLOSED / ANOMALI
   constraint CK_as_status check (session_status IN ('OPEN','CLOSED','ANOMALI')),
 session_flag varchar(30) null,             -- LEMBUR_DIKONFIRMASI / BELUM_CHECKOUT /
                                            -- LUPA_KEMBALI / DIKOREKSI / DIVERIFIKASI
 entry_source varchar(10) not null          -- GATE / MANUAL
   constraint CK_as_entry_source check (entry_source IN ('GATE','MANUAL')),
 remarks varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,                   -- user sistem gate_system untuk sesi dari gate
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 -- ANOMALI = ditutup paksa, check_out_at WAJIB NULL (jamnya tidak diketahui, bukan ditebak);
 -- OPEN = kartu sedang diambil, orang ada di dalam.
 constraint CK_as_checkout_shape check (
     (session_status = 'CLOSED' AND check_out_at IS NOT NULL)
  OR (session_status <> 'CLOSED' AND check_out_at IS NULL)
 )
);
GO

-- Log MENTAH: tidak ada update, tidak ada soft delete.
CREATE TABLE gate_taps(
 gate_tap_id int primary key identity(1,1),
 tap_uid uniqueidentifier not null,         -- digenerate GateApp, kunci idempoten
 card_uid varchar(20) not null,
 tapped_at datetime2 not null,              -- WAKTU TAP ASLI dari gate, BUKAN waktu terima server
 gate_code varchar(30) not null,
 result_code varchar(30) not null,
 attendance_session_id int null
   constraint FK_gt_sessions foreign key references attendance_sessions(attendance_session_id),
 employee_id int null                       -- NULL kalau kartu tidak dikenal
   constraint FK_gt_employees foreign key references employees(employee_id),
 is_offline_replay bit not null
   constraint DF_gt_offline_replay default 0,
 created_at datetime2 not null default sysdatetime()
);
GO

-- Log MENTAH. Tanpa tabel ini, data karyawan bisa berubah dari gate tanpa jejak.
CREATE TABLE employee_change_log(
 employee_change_log_id int primary key identity(1,1),
 employee_id int not null
   constraint FK_ecl_employees foreign key references employees(employee_id),
 field_name varchar(50) not null,           -- employee_name / phone_no (nama kolom asli)
 old_value varchar(255) null,
 new_value varchar(255) null,
 changed_by_employee_id int null            -- satpam, kalau dari gate
   constraint FK_ecl_changed_by_employee foreign key references employees(employee_id),
 source varchar(10) not null                -- GATE / ADMIN
   constraint CK_ecl_source check (source IN ('GATE','ADMIN')),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null
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
CREATE UNIQUE INDEX UX_print_devices_code      ON print_devices(device_code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_print_job_routes_type   ON print_job_routes(job_type) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_print_kupon_job_types_job_type ON print_kupon_job_types(job_type) WHERE deleted_at IS NULL;
-- Prompt 55.
CREATE UNIQUE INDEX UX_payroll_periods_year_no ON payroll_periods(period_year, period_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX UX_payroll_periods_code   ON payroll_periods(period_code)             WHERE deleted_at IS NULL;
-- Satu baris log maksimal punya SATU lock aktif.
CREATE UNIQUE INDEX UX_wli_log_active         ON workflow_lock_items(workflow_log_id)     WHERE released_at IS NULL AND deleted_at IS NULL;
-- Prompt 58: satu pegawai maksimal satu baris absen per tanggal (resource TIDAK ikut --
-- pegawai hanya bisa anggota satu line).
CREATE UNIQUE INDEX UX_ea_employee_date       ON employee_attendances(employee_id, attendance_date) WHERE deleted_at IS NULL;
-- Prompt 58 (lanjutan): satu jabatan maksimal satu baris aktif per divisi.
CREATE UNIQUE INDEX UX_divpos_division_position ON division_positions(division_id, position_id)  WHERE deleted_at IS NULL;
-- Prompt 70: satu UID hanya boleh AKTIF di satu karyawan, tapi kartu lama yang sudah NONAKTIF
-- tetap tersimpan sebagai riwayat (kartu hilang/diganti) -- itulah sebabnya card_status ikut
-- masuk klausa WHERE, bukan cuma deleted_at.
CREATE UNIQUE INDEX UX_employee_cards_uid     ON employee_cards(card_uid)      WHERE deleted_at IS NULL AND card_status = 'AKTIF';
-- Hanya boleh ada SATU sesi OPEN per karyawan -- beberapa kartu aktif milik satu orang tetap
-- bermuara ke satu sesi.
CREATE UNIQUE INDEX UX_as_open_per_employee   ON attendance_sessions(employee_id) WHERE session_status = 'OPEN' AND deleted_at IS NULL;
-- Inilah yang mencegah tap terhitung dua kali kalau jaringan putus setelah server commit tapi
-- sebelum GateApp menerima balasan (GateApp mengirim ulang baris antrian yang sama).
CREATE UNIQUE INDEX UX_gate_taps_tap_uid      ON gate_taps(tap_uid);
GO

-- ============ 11. INDEX FK UNTUK PERFORMA QUERY HARIAN ============

CREATE INDEX IX_ddp_plan_date       ON daily_division_plans(plan_date) WHERE deleted_at IS NULL;
CREATE INDEX IX_movement_stock      ON material_movement(stock_id)  WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_bundle          ON article_workflow_logs(bundle_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_article_workflow ON article_workflow_logs(article_workflow_id) WHERE deleted_at IS NULL;
-- Prompt 47: modul Log Aktivitas -- filter rentang created_at/received_at langsung.
CREATE INDEX IX_awl_created_at      ON article_workflow_logs(created_at) WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_received_at     ON article_workflow_logs(received_at) WHERE deleted_at IS NULL;
CREATE INDEX IX_bundles_article     ON bundles(article_id);
CREATE INDEX IX_articles_project    ON articles(project_id);
CREATE INDEX IX_stocks_material     ON material_stocks(material_id);
CREATE INDEX IX_stations_division   ON stations(division_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_status   ON print_jobs([status]) WHERE deleted_at IS NULL;
CREATE INDEX IX_print_jobs_ref      ON print_jobs(job_type, ref_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_packs_project       ON packs(project_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_pack_items_pack     ON pack_items(pack_id) WHERE deleted_at IS NULL;
-- Prompt 55.
CREATE INDEX IX_awl_lock_id         ON article_workflow_logs(lock_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_wli_lock_id         ON workflow_lock_items(lock_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_uri_request_id      ON unlock_request_items(request_id);
-- Prompt 58: list & rekap absen per line per tanggal; pencarian no. telp (BUKAN unique --
-- keunikan dicek di SP supaya nomor pegawai nonaktif bisa ditawarkan "Aktifkan lagi?").
CREATE INDEX IX_ea_resource_date     ON employee_attendances(resource_id, attendance_date) WHERE deleted_at IS NULL;
CREATE INDEX IX_employees_phone_no   ON employees(phone_no) WHERE deleted_at IS NULL AND phone_no IS NOT NULL;
-- Prompt 59: rekap produksi stasiun membaca non-PO per resource + periode.
CREATE INDEX IX_npo_resource_period  ON non_po_outputs(resource_id, payroll_period_id) WHERE deleted_at IS NULL;
-- Prompt 70: absensi RFID. SENGAJA TIDAK unique per employee di employee_cards -- satu karyawan
-- boleh punya beberapa kartu AKTIF sekaligus (kartu tetap + kartu sementara).
CREATE INDEX IX_employee_cards_employee ON employee_cards(employee_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_as_date_division     ON attendance_sessions(work_date, division_id) WHERE deleted_at IS NULL;
CREATE INDEX IX_as_employee_date     ON attendance_sessions(employee_id, work_date) WHERE deleted_at IS NULL;
-- Cooldown 30 detik SIS_Gate_Tap dibaca dari index ini.
CREATE INDEX IX_gate_taps_card_time  ON gate_taps(card_uid, tapped_at DESC);
CREATE INDEX IX_ecl_employee         ON employee_change_log(employee_id, created_at DESC);
GO

-- ============ 12. FK YANG BARU BISA DIPASANG SETELAH SEMUA TABEL ADA ============
-- article_workflow_logs (bagian 5) menunjuk workflow_locks (bagian 9g) sementara
-- workflow_lock_items menunjuk balik ke article_workflow_logs -- siklus ini dipecah dengan
-- memasang FK arah ini paling akhir. Lihat juga sql/alter_55_workflow_lock.sql.

ALTER TABLE article_workflow_logs ADD CONSTRAINT FK_awl_workflow_locks
    FOREIGN KEY (lock_id) REFERENCES workflow_locks(lock_id);
GO
