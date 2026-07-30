-- Prompt 34: flag auto-terima per step workflow (workflow_template_steps + article_workflows).
-- Jalankan manual, idempotent.

IF COL_LENGTH('workflow_template_steps', 'auto_receive') IS NULL
BEGIN
    ALTER TABLE workflow_template_steps
      ADD auto_receive bit NOT NULL CONSTRAINT DF_wts_auto_receive DEFAULT 0;
END

IF COL_LENGTH('article_workflows', 'auto_receive') IS NULL
BEGIN
    ALTER TABLE article_workflows
      ADD auto_receive bit NOT NULL CONSTRAINT DF_aw_auto_receive DEFAULT 0;
END
