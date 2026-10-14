/* =============================================================
   Module Stok Benang (Prompt 71) -- SP master schema `inv`:
   jenis benang, merk, lokasi (rak), dan SKU.

   Aturan CLAUDE.md:
   - mutasi : inv.SIS_<Nama>_Manage dengan @Action
   - read   : SP terpisah bernama fungsional (_List / _GetById / _GetBySku)
   - seluruh validasi bisnis di sini (RAISERROR bahasa Indonesia), API hanya
     meneruskan pesan ke UI.
   - soft delete: semua query hanya baris deleted_at IS NULL.

   ANSI_NULLS / QUOTED_IDENTIFIER wajib ON: tabel inv.* punya filtered unique
   index (UX_inv_thread_*).

   CATATAN sku_code: dibuat SEKALI saat CREATE dan TIDAK pernah berubah saat
   UPDATE -- label QR `TB:<sku_code>` sudah tertempel di paper tube kones yang
   ada di rak, jadi mengubahnya akan membuat label lama tidak dikenali.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Buang semua karakter selain A-Z dan 0-9, hasil uppercase. Dipakai menyusun sku_code.
-- Dibuat PALING AWAL di file ini karena dipanggil inv.SIS_ThreadItem_Manage.
CREATE OR ALTER FUNCTION inv.fn_ThreadAlnum (@Value VARCHAR(200))
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @Out VARCHAR(200) = UPPER(ISNULL(@Value, ''));
    DECLARE @Pos INT = PATINDEX('%[^A-Z0-9]%', @Out);

    WHILE @Pos > 0
    BEGIN
        SET @Out = STUFF(@Out, @Pos, 1, '');
        SET @Pos = PATINDEX('%[^A-Z0-9]%', @Out);
    END

    RETURN @Out;
END;
GO

-- =============================================================
-- JENIS BENANG
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadType_Manage
    @Action    VARCHAR(20),          -- CREATE | UPDATE | DELETE
    @Id        INT = NULL,
    @Code      VARCHAR(20) = NULL,
    @Name      VARCHAR(50) = NULL,
    @SortOrder INT = NULL,
    @UserId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE','UPDATE')
    BEGIN
        SET @Code = UPPER(LTRIM(RTRIM(ISNULL(@Code,''))));
        SET @Name = LTRIM(RTRIM(ISNULL(@Name,'')));

        IF @Code = ''
        BEGIN
            RAISERROR('Kode jenis benang wajib diisi.', 16, 1);
            RETURN;
        END

        IF @Name = ''
        BEGIN
            RAISERROR('Nama jenis benang wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_types
                    WHERE code = @Code AND deleted_at IS NULL
                      AND (@Action = 'CREATE' OR thread_type_id <> @Id))
        BEGIN
            RAISERROR('Kode jenis benang "%s" sudah dipakai.', 16, 1, @Code);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO inv.thread_types (code, name, sort_order, created_by)
        VALUES (@Code, @Name, ISNULL(@SortOrder, 0), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_types WHERE thread_type_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Jenis benang tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_types
        SET code = @Code,
            name = @Name,
            sort_order = ISNULL(@SortOrder, sort_order),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE thread_type_id = @Id;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_items
                    WHERE thread_type_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Jenis benang ini masih dipakai SKU -- tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_types
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE thread_type_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
END;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadType_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT t.thread_type_id AS ThreadTypeId,
           t.code           AS Code,
           t.name           AS Name,
           t.sort_order     AS SortOrder,
           (SELECT COUNT(*) FROM inv.thread_items i
             WHERE i.thread_type_id = t.thread_type_id AND i.deleted_at IS NULL) AS ItemCount
    FROM inv.thread_types t
    WHERE t.deleted_at IS NULL
    ORDER BY t.sort_order, t.name;
END;
GO

-- =============================================================
-- MERK
-- CREATE boleh dipanggil inline dari form SKU -- id merk baru dikembalikan
-- sebagai kolom Value supaya form langsung bisa memilihnya.
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadBrand_Manage
    @Action VARCHAR(20),              -- CREATE | UPDATE | DELETE
    @Id     INT = NULL,
    @Name   VARCHAR(100) = NULL,
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE','UPDATE')
    BEGIN
        SET @Name = LTRIM(RTRIM(ISNULL(@Name,'')));

        IF @Name = ''
        BEGIN
            RAISERROR('Nama merk wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_brands
                    WHERE name = @Name AND deleted_at IS NULL
                      AND (@Action = 'CREATE' OR thread_brand_id <> @Id))
        BEGIN
            RAISERROR('Merk "%s" sudah ada.', 16, 1, @Name);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO inv.thread_brands (name, created_by)
        VALUES (@Name, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_brands WHERE thread_brand_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Merk tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_brands
        SET name = @Name, updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE thread_brand_id = @Id;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_items
                    WHERE thread_brand_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Merk ini masih dipakai SKU -- tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_brands
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE thread_brand_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
END;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadBrand_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.thread_brand_id AS ThreadBrandId,
           b.name            AS Name,
           (SELECT COUNT(*) FROM inv.thread_items i
             WHERE i.thread_brand_id = b.thread_brand_id AND i.deleted_at IS NULL) AS ItemCount
    FROM inv.thread_brands b
    WHERE b.deleted_at IS NULL
    ORDER BY b.name;
END;
GO

-- =============================================================
-- LOKASI (RAK)
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadLocation_Manage
    @Action    VARCHAR(20),           -- CREATE | UPDATE | DELETE | SETACTIVE
    @Id        INT = NULL,
    @Code      VARCHAR(20) = NULL,
    @Name      VARCHAR(100) = NULL,
    @SortOrder INT = NULL,
    @IsActive  BIT = NULL,
    @UserId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE','UPDATE')
    BEGIN
        SET @Code = UPPER(LTRIM(RTRIM(ISNULL(@Code,''))));
        SET @Name = NULLIF(LTRIM(RTRIM(ISNULL(@Name,''))), '');

        IF @Code = ''
        BEGIN
            RAISERROR('Kode rak wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_locations
                    WHERE code = @Code AND deleted_at IS NULL
                      AND (@Action = 'CREATE' OR thread_location_id <> @Id))
        BEGIN
            RAISERROR('Kode rak "%s" sudah dipakai.', 16, 1, @Code);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO inv.thread_locations (code, name, sort_order, is_active, created_by)
        VALUES (@Code, @Name, ISNULL(@SortOrder, 0), 1, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_locations WHERE thread_location_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Rak tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_locations
        SET code = @Code,
            name = @Name,
            sort_order = ISNULL(@SortOrder, sort_order),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE thread_location_id = @Id;
        RETURN;
    END

    IF @Action = 'SETACTIVE'
    BEGIN
        IF @IsActive IS NULL
        BEGIN
            RAISERROR('Status aktif wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_locations
        SET is_active = @IsActive, updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE thread_location_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_stocks
                    WHERE thread_location_id = @Id AND deleted_at IS NULL AND qty_whole > 0)
        BEGIN
            RAISERROR('Rak ini masih berisi kones whole -- pindahkan dulu isinya sebelum dihapus.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_split_cones
                    WHERE thread_location_id = @Id AND deleted_at IS NULL AND [status] = 'IN_STOCK')
        BEGIN
            RAISERROR('Rak ini masih berisi kones split -- pindahkan dulu isinya sebelum dihapus.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_locations
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE thread_location_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
END;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadLocation_List
    @HanyaAktif BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.thread_location_id AS ThreadLocationId,
           l.code               AS Code,
           l.name               AS Name,
           l.sort_order         AS SortOrder,
           l.is_active          AS IsActive,
           ISNULL(w.item_count, 0)      AS ItemCount,
           ISNULL(w.qty_whole_total, 0) AS QtyWholeTotal,
           ISNULL(s.split_count, 0)     AS SplitCount
    FROM inv.thread_locations l
    OUTER APPLY (
        SELECT COUNT(*) AS item_count, SUM(st.qty_whole) AS qty_whole_total
        FROM inv.thread_stocks st
        WHERE st.thread_location_id = l.thread_location_id
          AND st.deleted_at IS NULL
          AND st.qty_whole > 0
    ) w
    OUTER APPLY (
        SELECT COUNT(*) AS split_count
        FROM inv.thread_split_cones c
        WHERE c.thread_location_id = l.thread_location_id
          AND c.deleted_at IS NULL
          AND c.[status] = 'IN_STOCK'
    ) s
    WHERE l.deleted_at IS NULL
      AND (@HanyaAktif = 0 OR l.is_active = 1)
    ORDER BY l.sort_order, l.code;
END;
GO

-- =============================================================
-- SKU BENANG
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadItem_Manage
    @Action     VARCHAR(20),          -- CREATE | UPDATE | DELETE | SETACTIVE | SETPHOTO
    @Id         INT = NULL,
    @TypeId     INT = NULL,
    @BrandId    INT = NULL,
    @ColorName  VARCHAR(100) = NULL,
    @ColorCode  VARCHAR(30) = NULL,
    @ConeSize   VARCHAR(10) = NULL,   -- KECIL | BESAR
    @PhotoPath  VARCHAR(255) = NULL,  -- SETPHOTO; NULL = hapus foto
    @IsActive   BIT = NULL,
    @UserId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE','UPDATE')
    BEGIN
        SET @ColorName = LTRIM(RTRIM(ISNULL(@ColorName,'')));
        SET @ColorCode = UPPER(LTRIM(RTRIM(ISNULL(@ColorCode,''))));
        SET @ConeSize  = UPPER(LTRIM(RTRIM(ISNULL(@ConeSize,''))));

        IF @ColorName = ''
        BEGIN
            RAISERROR('Nama warna wajib diisi.', 16, 1);
            RETURN;
        END

        IF @ColorCode = ''
        BEGIN
            RAISERROR('Kode warna wajib diisi.', 16, 1);
            RETURN;
        END

        IF @ConeSize NOT IN ('KECIL','BESAR')
        BEGIN
            RAISERROR('Jenis kones harus KECIL atau BESAR.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM inv.thread_types
                        WHERE thread_type_id = @TypeId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Jenis benang tidak dikenal.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM inv.thread_brands
                        WHERE thread_brand_id = @BrandId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Merk benang tidak dikenal.', 16, 1);
            RETURN;
        END

        -- SKU kembar = kombinasi jenis + merk + kode warna + jenis kones yang sama.
        IF EXISTS (SELECT 1 FROM inv.thread_items
                    WHERE thread_type_id = @TypeId
                      AND thread_brand_id = @BrandId
                      AND color_code = @ColorCode
                      AND cone_size = @ConeSize
                      AND deleted_at IS NULL
                      AND (@Action = 'CREATE' OR thread_item_id <> @Id))
        BEGIN
            RAISERROR('SKU dengan jenis, merk, kode warna, dan jenis kones yang sama sudah ada.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        -- --- rakit sku_code: BN-<TYPE3>-<BRAND3>-<KODEWARNA>-<K|B> ---
        DECLARE @TypeCode VARCHAR(20), @BrandName VARCHAR(100);
        SELECT @TypeCode = code FROM inv.thread_types WHERE thread_type_id = @TypeId;
        SELECT @BrandName = name FROM inv.thread_brands WHERE thread_brand_id = @BrandId;

        DECLARE @TypePart VARCHAR(20) = inv.fn_ThreadAlnum(@TypeCode);
        DECLARE @BrandPart VARCHAR(100) = inv.fn_ThreadAlnum(@BrandName);
        DECLARE @ColorPart VARCHAR(30) = inv.fn_ThreadAlnum(@ColorCode);

        IF @ColorPart = '' SET @ColorPart = 'X';

        DECLARE @Base VARCHAR(40) =
            'BN-' + LEFT(@TypePart, 3) + '-' + LEFT(@BrandPart, 3) + '-' + @ColorPart
            + '-' + CASE WHEN @ConeSize = 'KECIL' THEN 'K' ELSE 'B' END;

        DECLARE @Sku VARCHAR(40) = @Base;
        DECLARE @Suffix INT = 1;

        WHILE EXISTS (SELECT 1 FROM inv.thread_items WHERE sku_code = @Sku AND deleted_at IS NULL)
        BEGIN
            SET @Suffix = @Suffix + 1;
            SET @Sku = LEFT(@Base, 40 - LEN(CAST(@Suffix AS VARCHAR(10))) - 1)
                       + '-' + CAST(@Suffix AS VARCHAR(10));
        END

        INSERT INTO inv.thread_items
            (sku_code, thread_type_id, thread_brand_id, color_name, color_code,
             cone_size, photo_path, is_active, created_by)
        VALUES
            (@Sku, @TypeId, @BrandId, @ColorName, @ColorCode,
             @ConeSize, NULL, 1, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_items WHERE thread_item_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- sku_code SENGAJA tidak diubah: label QR lama harus tetap dikenali.
        UPDATE inv.thread_items
        SET thread_type_id = @TypeId,
            thread_brand_id = @BrandId,
            color_name = @ColorName,
            color_code = @ColorCode,
            cone_size = @ConeSize,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE thread_item_id = @Id;
        RETURN;
    END

    IF @Action = 'SETPHOTO'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_items WHERE thread_item_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_items
        SET photo_path = NULLIF(LTRIM(RTRIM(ISNULL(@PhotoPath,''))), ''),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE thread_item_id = @Id;
        RETURN;
    END

    IF @Action = 'SETACTIVE'
    BEGIN
        IF @IsActive IS NULL
        BEGIN
            RAISERROR('Status aktif wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_items
        SET is_active = @IsActive, updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE thread_item_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_movements
                    WHERE thread_item_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU ini sudah punya riwayat mutasi -- nonaktifkan saja, jangan dihapus.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_split_cones
                    WHERE thread_item_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU ini masih punya kones split -- tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM inv.thread_stocks
                    WHERE thread_item_id = @Id AND deleted_at IS NULL AND qty_whole > 0)
        BEGIN
            RAISERROR('SKU ini masih punya stok di rak -- tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE inv.thread_items
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE thread_item_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
END;
GO

-- -------------------------------------------------------------
-- LIST: paged + search + filter. TotalCount dibawa di tiap baris
-- (pola sama dengan tni.SIS_Stok_Riwayat) supaya satu round trip.
-- -------------------------------------------------------------
CREATE OR ALTER PROCEDURE inv.SIS_ThreadItem_List
    @Search        VARCHAR(100) = NULL,   -- warna, kode warna, merk, sku_code
    @TypeId        INT = NULL,
    @LocationId    INT = NULL,            -- hanya SKU yang punya isi di rak ini
    @HanyaAktif    BIT = 0,
    @SortColumn    VARCHAR(30) = NULL,    -- COLOR | SKU | TYPE | BRAND | QTY
    @SortDirection VARCHAR(4) = 'asc',
    @PageNumber    INT = 1,
    @PageSize      INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @PageNumber IS NULL OR @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 500 SET @PageSize = 50;
    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search,''))), '');

    DECLARE @Desc BIT = CASE WHEN LOWER(ISNULL(@SortDirection,'asc')) = 'desc' THEN 1 ELSE 0 END;
    DECLARE @Sort VARCHAR(30) = UPPER(ISNULL(@SortColumn, 'COLOR'));

    ;WITH src AS (
        SELECT i.thread_item_id,
               i.sku_code,
               i.color_name,
               i.color_code,
               i.cone_size,
               i.photo_path,
               i.is_active,
               t.thread_type_id,
               t.code AS type_code,
               t.name AS type_name,
               b.thread_brand_id,
               b.name AS brand_name,
               v.qty_whole_total,
               v.split_count_in_stock,
               v.split_gram_in_stock,
               v.split_count_issued,
               v.location_codes
        FROM inv.thread_items i
        INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
        INNER JOIN inv.v_thread_item_stock v ON v.thread_item_id = i.thread_item_id
        WHERE i.deleted_at IS NULL
          AND (@HanyaAktif = 0 OR i.is_active = 1)
          AND (@TypeId IS NULL OR i.thread_type_id = @TypeId)
          AND (@LocationId IS NULL OR EXISTS (
                SELECT 1 FROM inv.thread_stocks st
                WHERE st.thread_item_id = i.thread_item_id
                  AND st.thread_location_id = @LocationId
                  AND st.deleted_at IS NULL
                  AND st.qty_whole > 0)
               OR EXISTS (
                SELECT 1 FROM inv.thread_split_cones c
                WHERE c.thread_item_id = i.thread_item_id
                  AND c.thread_location_id = @LocationId
                  AND c.deleted_at IS NULL
                  AND c.[status] = 'IN_STOCK'))
          AND (@Search IS NULL
               OR i.color_name LIKE '%' + @Search + '%'
               OR i.color_code LIKE '%' + @Search + '%'
               OR i.sku_code   LIKE '%' + @Search + '%'
               OR b.name       LIKE '%' + @Search + '%')
    )
    SELECT thread_item_id        AS ThreadItemId,
           sku_code              AS SkuCode,
           color_name            AS ColorName,
           color_code            AS ColorCode,
           cone_size             AS ConeSize,
           photo_path            AS PhotoPath,
           is_active             AS IsActive,
           thread_type_id        AS ThreadTypeId,
           type_code             AS TypeCode,
           type_name             AS TypeName,
           thread_brand_id       AS ThreadBrandId,
           brand_name            AS BrandName,
           qty_whole_total       AS QtyWholeTotal,
           split_count_in_stock  AS SplitCountInStock,
           split_gram_in_stock   AS SplitGramInStock,
           split_count_issued    AS SplitCountIssued,
           location_codes        AS LocationCodes,
           COUNT(*) OVER ()      AS TotalCount
    FROM src
    -- Urut QTY memakai kolom angka; untuk itu CASE teks di bawah HARUS NULL saat
    -- @Sort = 'QTY', kalau tidak hasilnya terurut nama warna dulu, baru qty.
    ORDER BY
        CASE WHEN @Desc = 0 THEN
            CASE @Sort WHEN 'SKU' THEN sku_code
                       WHEN 'TYPE' THEN type_name
                       WHEN 'BRAND' THEN brand_name
                       WHEN 'QTY' THEN NULL
                       ELSE color_name END
        END ASC,
        CASE WHEN @Desc = 1 THEN
            CASE @Sort WHEN 'SKU' THEN sku_code
                       WHEN 'TYPE' THEN type_name
                       WHEN 'BRAND' THEN brand_name
                       WHEN 'QTY' THEN NULL
                       ELSE color_name END
        END DESC,
        CASE WHEN @Sort = 'QTY' AND @Desc = 0 THEN qty_whole_total END ASC,
        CASE WHEN @Sort = 'QTY' AND @Desc = 1 THEN qty_whole_total END DESC,
        thread_item_id
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- -------------------------------------------------------------
-- GET BY ID -- tiga result set: detail, stok per lokasi, kones split.
-- @Bagian membatasi ke SATU result set: EF Core (SqlQueryRaw) hanya bisa
-- membaca satu result set per pemanggilan, jadi API memanggil 3x
-- ('ITEM' / 'LOKASI' / 'SPLIT'). @Bagian NULL = ketiganya (dipakai saat
-- verifikasi langsung lewat sqlcmd).
-- -------------------------------------------------------------
CREATE OR ALTER PROCEDURE inv.SIS_ThreadItem_GetById
    @Id     INT,
    @Bagian VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Bagian IS NULL OR @Bagian = 'ITEM'
        SELECT i.thread_item_id        AS ThreadItemId,
               i.sku_code              AS SkuCode,
               i.color_name            AS ColorName,
               i.color_code            AS ColorCode,
               i.cone_size             AS ConeSize,
               i.photo_path            AS PhotoPath,
               i.is_active             AS IsActive,
               i.thread_type_id        AS ThreadTypeId,
               t.code                  AS TypeCode,
               t.name                  AS TypeName,
               i.thread_brand_id       AS ThreadBrandId,
               b.name                  AS BrandName,
               v.qty_whole_total       AS QtyWholeTotal,
               v.split_count_in_stock  AS SplitCountInStock,
               v.split_gram_in_stock   AS SplitGramInStock,
               v.split_count_issued    AS SplitCountIssued,
               v.location_codes        AS LocationCodes,
               1                       AS TotalCount
        FROM inv.thread_items i
        INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
        INNER JOIN inv.v_thread_item_stock v ON v.thread_item_id = i.thread_item_id
        WHERE i.thread_item_id = @Id AND i.deleted_at IS NULL;

    IF @Bagian IS NULL OR @Bagian = 'LOKASI'
        SELECT l.thread_location_id AS ThreadLocationId,
               l.code               AS Code,
               l.name               AS Name,
               st.qty_whole         AS QtyWhole,
               (SELECT COUNT(*) FROM inv.thread_split_cones c
                 WHERE c.thread_item_id = @Id
                   AND c.thread_location_id = l.thread_location_id
                   AND c.deleted_at IS NULL
                   AND c.[status] = 'IN_STOCK') AS SplitCount
        FROM inv.thread_stocks st
        INNER JOIN inv.thread_locations l ON l.thread_location_id = st.thread_location_id
        WHERE st.thread_item_id = @Id
          AND st.deleted_at IS NULL
          AND l.deleted_at IS NULL
          AND st.qty_whole > 0
        ORDER BY l.sort_order, l.code;

    IF @Bagian IS NULL OR @Bagian = 'SPLIT'
        SELECT c.thread_split_cone_id AS ThreadSplitConeId,
               c.cone_code            AS ConeCode,
               c.thread_item_id       AS ThreadItemId,
               c.weight_gram          AS WeightGram,
               c.[status]             AS Status,
               c.thread_location_id   AS ThreadLocationId,
               l.code                 AS LocationCode,
               c.issued_to_resource_id AS IssuedToResourceId,
               r.resource_name        AS IssuedToResourceName,
               c.issued_project_id    AS IssuedProjectId,
               p.project_name         AS IssuedProjectName,
               c.created_at           AS CreatedAt
        FROM inv.thread_split_cones c
        LEFT JOIN inv.thread_locations l ON l.thread_location_id = c.thread_location_id
        LEFT JOIN dbo.resources r        ON r.resource_id = c.issued_to_resource_id
        LEFT JOIN dbo.projects p         ON p.project_id = c.issued_project_id
        WHERE c.thread_item_id = @Id
          AND c.deleted_at IS NULL
          AND c.[status] IN ('IN_STOCK','ISSUED')
        ORDER BY CASE c.[status] WHEN 'IN_STOCK' THEN 0 ELSE 1 END,
                 c.weight_gram DESC, c.cone_code;
END;
GO

-- Hasil scan QR label SKU: `TB:<sku_code>` -> detail SKU. Bentuk result set
-- SAMA PERSIS dengan bagian ITEM di _GetById (DTO dipakai bersama).
CREATE OR ALTER PROCEDURE inv.SIS_ThreadItem_GetBySku
    @SkuCode VARCHAR(40)
AS
BEGIN
    SET NOCOUNT ON;

    SET @SkuCode = UPPER(LTRIM(RTRIM(ISNULL(@SkuCode,''))));

    -- toleran terhadap isi QR mentah `TB:BN-...`
    IF LEFT(@SkuCode, 3) = 'TB:' SET @SkuCode = LTRIM(SUBSTRING(@SkuCode, 4, 40));

    SELECT i.thread_item_id        AS ThreadItemId,
           i.sku_code              AS SkuCode,
           i.color_name            AS ColorName,
           i.color_code            AS ColorCode,
           i.cone_size             AS ConeSize,
           i.photo_path            AS PhotoPath,
           i.is_active             AS IsActive,
           i.thread_type_id        AS ThreadTypeId,
           t.code                  AS TypeCode,
           t.name                  AS TypeName,
           i.thread_brand_id       AS ThreadBrandId,
           b.name                  AS BrandName,
           v.qty_whole_total       AS QtyWholeTotal,
           v.split_count_in_stock  AS SplitCountInStock,
           v.split_gram_in_stock   AS SplitGramInStock,
           v.split_count_issued    AS SplitCountIssued,
           v.location_codes        AS LocationCodes,
           1                       AS TotalCount
    FROM inv.thread_items i
    INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
    INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
    INNER JOIN inv.v_thread_item_stock v ON v.thread_item_id = i.thread_item_id
    WHERE i.sku_code = @SkuCode AND i.deleted_at IS NULL;
END;
GO
