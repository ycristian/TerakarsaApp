-- Pengambilan data articles (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Article_Manage.sql (SIS_Article_Manage).
-- GetById hanya mengembalikan header; ukuran diambil terpisah lewat
-- SIS_ArticleSize_GetByArticle (EF SqlQueryRaw hanya baca 1 result set).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Article_GetByProject
    @ProjectId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.article_id AS Id, a.project_id AS ProjectId,
           a.size_pack_id AS SizePackId, sp.size_pack_name AS SizePackName,
           a.article_name AS ArticleName, a.style AS Style, a.color AS Color,
           ISNULL(SUM(asz.qty), 0) AS TotalQty,
           (SELECT COUNT(*) FROM article_photos ap WHERE ap.article_id = a.article_id AND ap.deleted_at IS NULL) AS PhotoCount
    FROM articles a
    INNER JOIN size_packs sp ON sp.size_pack_id = a.size_pack_id
    LEFT JOIN article_sizes asz ON asz.article_id = a.article_id AND asz.deleted_at IS NULL
    WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL
    GROUP BY a.article_id, a.project_id, a.size_pack_id, sp.size_pack_name, a.article_name, a.style, a.color
    ORDER BY a.article_id ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Article_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.article_id AS Id, a.project_id AS ProjectId,
           a.size_pack_id AS SizePackId, sp.size_pack_name AS SizePackName,
           a.article_name AS ArticleName, a.style AS Style, a.color AS Color,
           a.created_at AS CreatedAt, a.created_by AS CreatedBy,
           a.updated_at AS UpdatedAt, a.updated_by AS UpdatedBy
    FROM articles a
    INNER JOIN size_packs sp ON sp.size_pack_id = a.size_pack_id
    WHERE a.article_id = @Id AND a.deleted_at IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE SIS_ArticleSize_GetByArticle
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT asz.article_size_id AS Id, asz.size_pack_detail_id AS SizePackDetailId,
           spd.size_name AS SizeName, spd.sort_order AS SortOrder,
           asz.qty AS Qty, asz.bundle_qty AS BundleQty
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE asz.article_id = @ArticleId AND asz.deleted_at IS NULL
    ORDER BY spd.sort_order ASC, spd.size_pack_detail_id ASC;
END;
GO

-- Ringkasan ukuran untuk semua artikel dalam satu project sekaligus (1 round-trip),
-- dipakai buat menampilkan list size (mis. "S : 6") di panel Artikel halaman Data Project.
CREATE OR ALTER PROCEDURE SIS_ArticleSize_GetByProject
    @ProjectId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT asz.article_id AS ArticleId, spd.size_name AS SizeName,
           spd.sort_order AS SortOrder, asz.qty AS Qty
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    INNER JOIN articles a ON a.article_id = asz.article_id
    WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL AND asz.deleted_at IS NULL
    ORDER BY asz.article_id ASC, spd.sort_order ASC, spd.size_pack_detail_id ASC;
END;
GO
