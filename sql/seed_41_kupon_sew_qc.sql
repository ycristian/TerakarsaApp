-- Prompt 41 (lanjutan) -- OPSIONAL: aktifkan print_kupon = 1 untuk step Sewing + QC yang
-- sudah ada, baik di template maupun di workflow artikel yang sudah dibuat. Idempotent --
-- aman dijalankan berkali-kali. Pola sama dengan seed_34_auto_receive_buang_benang.sql:
-- dicari lewat step_name LIKE, bukan hardcode step_id. Hanya step ber-bundle yang kena
-- (requires_bundle = 1) -- v1 print_kupon memang ditolak SP di step non-bundle.

DECLARE @StepNamePatternSew VARCHAR(100) = '%sew%';
DECLARE @StepNamePatternQc VARCHAR(100) = '%qc%';

-- 0. Cek dulu (read-only) step mana yang bakal kena, sebelum commit ke UPDATE.
SELECT step_id, workflow_template_id, step_name, requires_bundle
FROM workflow_template_steps
WHERE deleted_at IS NULL AND requires_bundle = 1
  AND (step_name LIKE @StepNamePatternSew OR step_name LIKE @StepNamePatternQc);

-- 1. workflow_template_steps: semua baris hidup ber-bundle dengan nama cocok.
UPDATE workflow_template_steps
SET print_kupon = 1
WHERE deleted_at IS NULL AND requires_bundle = 1
  AND (step_name LIKE @StepNamePatternSew OR step_name LIKE @StepNamePatternQc);

PRINT 'workflow_template_steps diupdate: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- 2. article_workflows: semua baris hidup ber-bundle dengan nama cocok, lintas semua artikel.
UPDATE article_workflows
SET print_kupon = 1
WHERE deleted_at IS NULL AND requires_bundle = 1 AND is_bundling = 0
  AND (step_name LIKE @StepNamePatternSew OR step_name LIKE @StepNamePatternQc);

PRINT 'article_workflows diupdate: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
