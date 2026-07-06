-- Drop semua tabel TMOS.
-- Urutan sudah disusun: tabel anak (yang punya FK) dihapus lebih dulu,
-- jadi tidak akan kena error FK constraint. Aman dijalankan berulang.

-- Produksi & workflow
DROP TABLE IF EXISTS article_workflow_logs;
DROP TABLE IF EXISTS bundles;
DROP TABLE IF EXISTS article_sizes;
DROP TABLE IF EXISTS article_workflows;
DROP TABLE IF EXISTS workflow_template_steps;
DROP TABLE IF EXISTS workflow_templates;

-- Costing (refs projects, jadi sebelum projects)
DROP TABLE IF EXISTS cost_transactions;
DROP TABLE IF EXISTS cost_components;

-- Order intake
DROP TABLE IF EXISTS article_photos;
DROP TABLE IF EXISTS project_attachments;
DROP TABLE IF EXISTS articles;
DROP TABLE IF EXISTS size_pack_details;
DROP TABLE IF EXISTS size_packs;
DROP TABLE IF EXISTS projects;

-- Material: adjustment
DROP TABLE IF EXISTS material_adjustment_details;
DROP TABLE IF EXISTS material_adjustments;
DROP TABLE IF EXISTS material_adjustment_reasons;
DROP TABLE IF EXISTS material_adjustment_types;

-- Material: movement & stock (refs employees/resources, jadi sebelum keduanya)
DROP TABLE IF EXISTS material_movement;
DROP TABLE IF EXISTS material_movement_types;
DROP TABLE IF EXISTS material_stocks;
DROP TABLE IF EXISTS material_receipt_items;
DROP TABLE IF EXISTS material_receipts;
DROP TABLE IF EXISTS materials;
DROP TABLE IF EXISTS material_categories;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS suppliers;

-- Master organisasi (paling akhir karena paling banyak dirujuk)
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS resources;
DROP TABLE IF EXISTS resource_types;
DROP TABLE IF EXISTS positions;
DROP TABLE IF EXISTS divisions;
DROP TABLE IF EXISTS buyers;
