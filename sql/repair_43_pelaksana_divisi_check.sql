-- Prompt 43 -- Deteksi baris article_workflow_logs lama yang pelaksana/penerimanya BUKAN
-- resource milik divisi step/tujuan (lubang yang ditambal di sp_WorkflowLog_Manage.sql
-- CREATE & RECEIVE). Read-only, TIDAK ada blok eksekusi -- tidak ada cara algoritmis
-- menentukan resource yang benar untuk baris yang sudah terlanjur salah, jadi setiap baris
-- temuan harus ditangani manual per kasus (UNRECEIVE lalu RECEIVE ulang oleh resource yang
-- benar, atau REVISE_HANDOVER untuk baris yang belum diterima).
--
-- Jalankan SETELAH sp_WorkflowLog_Manage.sql versi Prompt 43 di-deploy, supaya baris baru
-- tidak lagi bisa salah -- skrip ini murni untuk membereskan riwayat.

SET NOCOUNT ON;

-- Bagian 1: resource_id (pelaksana) baris hidup tidak milik divisi step-nya sendiri.
SELECT
    awl.workflow_log_id,
    b.serial,
    aw.step_name AS step_name,
    dv_step.division_name AS division_step,
    r.resource_name AS pelaksana_tercatat,
    dv_resource.division_name AS divisi_resource_sebenarnya,
    awl.created_at
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
LEFT JOIN divisions dv_step ON dv_step.division_id = aw.division_id
INNER JOIN resources r ON r.resource_id = awl.resource_id
LEFT JOIN divisions dv_resource ON dv_resource.division_id = r.division_id
LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
WHERE awl.deleted_at IS NULL
  AND awl.resource_id IS NOT NULL
  AND r.division_id <> aw.division_id
ORDER BY awl.created_at;

-- Bagian 2: received_by_resource_id (penerima) baris hidup tidak milik divisi tujuannya.
SELECT
    awl.workflow_log_id,
    b.serial,
    aw.step_name AS step_name,
    dv_target.division_name AS division_tujuan,
    r.resource_name AS penerima_tercatat,
    dv_resource.division_name AS divisi_resource_sebenarnya,
    awl.received_at
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
LEFT JOIN divisions dv_target ON dv_target.division_id = awl.target_division_id
INNER JOIN resources r ON r.resource_id = awl.received_by_resource_id
LEFT JOIN divisions dv_resource ON dv_resource.division_id = r.division_id
LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
WHERE awl.deleted_at IS NULL
  AND awl.received_by_resource_id IS NOT NULL
  AND awl.target_division_id IS NOT NULL
  AND r.division_id <> awl.target_division_id
ORDER BY awl.received_at;
