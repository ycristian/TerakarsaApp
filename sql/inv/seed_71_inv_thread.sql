/* =============================================================
   Module Stok Benang (Prompt 71) -- seed master schema `inv`.
   Idempotent: aman dijalankan berulang, tidak menghapus data yang ada.

   created_by = 1 (user admin pertama) -- seed tidak punya user login.
   LOKASI (rak) SENGAJA TIDAK di-seed: dibuat admin gudang dari halaman
   /gudang/benang/lokasi, karena penamaan rak berbeda tiap gudang.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============ JENIS BENANG ============
-- Kode 3 huruf pertama ikut jadi bagian sku_code (POLY -> POL, COTTON -> COT, ...).
MERGE inv.thread_types AS t
USING (VALUES
    ('POLY',   'Poly',   10),
    ('COTTON', 'Cotton', 20),
    ('SPUN',   'Spun',   30),
    ('NYLON',  'Nylon',  40)
) AS s(code, name, sort_order)
    ON t.code = s.code AND t.deleted_at IS NULL
WHEN NOT MATCHED BY TARGET THEN
    INSERT (code, name, sort_order, created_by)
    VALUES (s.code, s.name, s.sort_order, 1);
GO

-- ============ KATEGORI ALASAN ADJUST (stock opname, Prompt 74) ============
-- requires_note = 1 hanya untuk LAINNYA.
MERGE inv.thread_reason_codes AS t
USING (VALUES
    ('HILANG',              'Hilang',                   CAST(0 AS BIT), 10),
    ('SALAH_INPUT',         'Salah input sebelumnya',   CAST(0 AS BIT), 20),
    ('PINDAH_TAK_TERCATAT', 'Pindahan belum dicatat',   CAST(0 AS BIT), 30),
    ('MASUK_TAK_TERCATAT',  'Masuk belum dicatat',      CAST(0 AS BIT), 40),
    ('RUSAK',               'Rusak / tidak terpakai',   CAST(0 AS BIT), 50),
    ('STOK_AWAL',           'Stok awal',                CAST(0 AS BIT), 60),
    ('LAINNYA',             'Lainnya',                  CAST(1 AS BIT), 70)
) AS s(code, name, requires_note, sort_order)
    ON t.code = s.code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (code, name, requires_note, sort_order, created_by)
    VALUES (s.code, s.name, s.requires_note, s.sort_order, 1);
GO
