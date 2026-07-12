-- Prompt 17: step Bundling implisit
ALTER TABLE article_workflows
  ADD is_bundling bit NOT NULL CONSTRAINT DF_aw_is_bundling DEFAULT 0;
GO
