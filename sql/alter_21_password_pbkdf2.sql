-- Prompt 21: pelebaran kolom password untuk format PBKDF2$iter$salt$hash
ALTER TABLE Users ALTER COLUMN Password varchar(500) NOT NULL;
GO
