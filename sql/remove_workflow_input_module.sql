-- Prompt 23: input step non-bundle pindah penuh ke station kiosk -- halaman /workflow-input
-- dan module WORKFLOW_INPUT (seed_workflow_input_module.sql, Prompt 12c) dihapus. Idempotent,
-- aman dijalankan berulang.

UPDATE Modules SET IsActive = 0 WHERE Code = 'WORKFLOW_INPUT' AND IsActive = 1;
GO

DELETE um
FROM UserModules um
INNER JOIN Modules m ON m.Id = um.ModuleId
WHERE m.Code = 'WORKFLOW_INPUT';
GO
