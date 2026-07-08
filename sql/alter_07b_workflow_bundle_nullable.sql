-- Prompt 7b: workflow log tanpa bundle untuk step pra-bundle (Cutting)

ALTER TABLE article_workflow_logs ALTER COLUMN bundle_id int NULL;
GO

ALTER TABLE workflow_template_steps
  ADD requires_bundle bit NOT NULL CONSTRAINT DF_wts_requires_bundle DEFAULT 1;
GO

ALTER TABLE article_workflows
  ADD requires_bundle bit NOT NULL CONSTRAINT DF_aw_requires_bundle DEFAULT 1;
GO
