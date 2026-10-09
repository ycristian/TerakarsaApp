-- =============================================================
-- Seed master pola PDH TNI AD 2026 (Prompt 61)
-- Sumber: 'Sampel data TNI AD 2026.xlsx' sheet SizePack Kemeja & SizePack Celana.
-- Digenerate otomatis -- jangan diketik ulang. Idempotent: baris yang kodenya sudah
-- ada (hidup) dilewati.
--
-- Catatan dari sumber:
--  * LD_136_PG muncul DUA KALI di SizePack Kemeja (kolom AG kode_alt 17,5-1 dan
--    kolom AH kode_alt 17,5-2) dengan ukuran berbeda. Yang dipakai: kolom AG.
--  * Kode LD_118_PG dipakai 1 personel di data mentah tetapi TIDAK ada di SizePack.
--  * Kolom AF di blok celana wanita punya angka tanpa kode -- diabaikan.
--  * Nilai 0 / kosong disimpan sebagai NULL.
-- =============================================================
SET NOCOUNT ON;
DECLARE @SeedUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
IF @SeedUserId IS NULL BEGIN RAISERROR('Tidak ada user Admin untuk created_by seed.',16,1); RETURN; END

-- ---------- KEMEJA (98 pola) ----------
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_82_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_82_P', NULL, 'P', 82, 36, 39, 82, 76, 86, 68, 31, 42, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_84_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_84_P', NULL, 'P', 84, 36, 39, 84, 78, 88, 68, 31, 42, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_86_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_86_P', NULL, 'P', 86, 37, 40, 86, 80, 90, 68, 32, 43, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_88_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_88_P', NULL, 'P', 88, 37, 41, 88, 82, 92, 68, 32, 43, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_90_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_90_P', NULL, 'P', 90, 35.5, 40, 90, 84, 88, 68, 32, 50, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_92_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_92_P', '14-1', 'P', 92, 36, 41, 92, 86, 90, 68, 34, 52, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_94_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_94_P', '14-2', 'P', 94, 36.5, 41, 94, 88, 92, 68, 34, 52, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_96_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_96_P', '14-3', 'P', 96, 37, 42, 96, 90, 94, 68, 35, 53, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_98_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_98_P', '14,5-1', 'P', 98, 37.5, 42, 98, 93, 96, 69, 35, 53, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_100_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_100_P', '14,5-2', 'P', 100, 38, 43, 100, 95, 98, 69, 36, 54, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_102_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_102_P', '14,5-3', 'P', 102, 38.5, 43, 102, 97, 100, 69, 36, 54, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_104_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_104_P', '15-1', 'P', 104, 39, 44, 104, 100, 102, 69, 37, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_106_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_106_P', '15-2', 'P', 106, 39.5, 44, 106, 102, 104, 69, 37, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_P', '15-3', 'P', 108, 40, 45, 108, 104, 106, 70, 38, 56, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_PG', NULL, 'PG', 108, 40, 46, 108, 114, 116, 74, 39, 57, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_110_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_110_P', '15,5-1', 'P', 110, 40.5, 45, 110, 106, 108, 70, 38, 56, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_110_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_110_PG', NULL, 'PG', 110, 40.5, 46, 110, 116, 118, 74, 39, 57, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_P', '15,5-2', 'P', 112, 41, 47, 112, 108, 114, 72, 39, 57, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_PG', NULL, 'PG', 112, 41, 48, 112, 118, 120, 76, 40, 58, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_P', '15,5-3', 'P', 114, 41.5, 47, 114, 110, 116, 74, 39, 57, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_PG', NULL, 'PG', 114, 41.5, 48, 114, 120, 122, 76, 40, 58, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_P', '16-1', 'P', 116, 42, 49, 116, 112, 118, 76, 41, 59, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_PG', NULL, 'PG', 116, 42, 48, 116, 122, 124, 76, 41, 59, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_118_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_118_P', '16-2', 'P', 118, 42.5, 49, 118, 114, 120, 76, 41, 59, 26, NULL, 1, @SeedUserId);
-- LD_118_PG: BUKAN dari grading Kang Wawan -- interpolasi LD_116_PG <-> LD_120_PG,
-- ditambahkan di fix 72 (2026-10-05) supaya 1 isian form bisa masuk. Seri PG aslinya
-- melangkah 108..116 lalu 120, jadi 118 bukan langkah grading. Konfirmasi ke pembuat
-- pola sebelum kain dipotong.
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_118_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_118_PG', NULL, 'PG', 118, 42.5, 50, 118, 124, 126.5, 76.5, 42.5, 60.5, 26.5, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_120_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_120_P', '16-3', 'P', 120, 43, 51, 120, 116, 122, 76, 43, 61, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_120_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_120_PG', '16,5-1', 'PG', 120, 43, 52, 120, 126, 129, 77, 44, 62, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_P', NULL, 'P', 124, 44, 52, 124, 120, 126, 76, 44, 62, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_PG', '16,5-2', 'PG', 124, 44, 53, 124, 130, 133, 77, 46, 63, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_128_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_128_PG', '17-1', 'PG', 128, 45, 54, 128, 134, 137, 78, 47, 64, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_132_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_132_PG', '17-2', 'PG', 132, 46, 55, 132, 138, 141, 78, 48, 65, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_136_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_136_PG', '17,5-1', 'PG', 136, 47, 56, 136, 142, 145, 78, 49, 66, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_140_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_140_PG', '18-1', 'PG', 140, 48, 58, 140, 146, 149, 79, 51, 68, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_144_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_144_PG', '18-4', 'PG', 144, 49, 59, 144, 150, 153, 79, 52, 69, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_148_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_148_PG', NULL, 'PG', 148, 50, 60, 148, 154, 157, 79, 53, 70, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_82_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_82_W', NULL, 'W', 82, NULL, NULL, 82, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_84_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_84_W', NULL, 'W', 84, 39, 38, 84, 74, 92, 68, 30, 41, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_86_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_86_W', NULL, 'W', 86, 39, 38, 86, 76, 94, 68, 30, 41, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_88_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_88_W', NULL, 'W', 88, 39, 39, 88, 80, 98, 68, 31, 42, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_90_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_90_W', NULL, 'W', 90, 42.5, 37, 90, 82, 88, 67, 32, 46, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_92_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_92_W', NULL, 'W', 92, 43, 38, 92, 84, 90, 67, 32, 46, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_94_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_94_W', NULL, 'W', 94, 43.5, 38, 94, 86, 92, 68, 33, 47, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_96_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_96_W', NULL, 'W', 96, 44, 39, 96, 88, 94, 68, 33, 47, 22, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_98_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_98_W', NULL, 'W', 98, 44.5, 39, 98, 90, 96, 69, 34, 48, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_100_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_100_W', NULL, 'W', 100, 45, 40, 100, 92, 98, 69, 34, 48, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_102_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_102_W', NULL, 'W', 102, 45.5, 40, 102, 94, 100, 70, 35, 49, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_104_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_104_W', NULL, 'W', 104, 46, 41, 104, 96, 102, 70, 35, 49, 23, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_106_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_106_W', NULL, 'W', 106, 46.5, 41, 106, 98, 104, 71, 36, 50, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_W', NULL, 'W', 108, 47, 42, 108, 100, 106, 71, 36, 50, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_W_PG', NULL, 'W_PG', 108, 47, 43, 108, 114, 122, 71, 38, 52, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_110_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_110_W', NULL, 'W', 110, 47.5, 42, 110, 102, 110, 72, 37, 51, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_W', NULL, 'W', 112, 48, 43, 112, 102, 112, 72, 37, 51, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_W_PG', NULL, 'W_PG', 112, 48, 44, 112, 118, 126, 72, 39, 53, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_W', NULL, 'W', 114, 48.5, 43, 114, 104, 116, 73, 39, 53, 24, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_W_PG', NULL, 'W_PG', 114, 48.5, 44, 114, 120, 128, 73, 41, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_W', NULL, 'W', 116, 49, 44, 116, 106, 118, 73, 39, 53, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_W_PG', NULL, 'W_PG', 116, 49, 45, 116, 122, 130, 75, 41, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_118_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_118_W', NULL, 'W', 118, 49.5, 44, 118, 108, 120, 74, 40, 54, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_120_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_120_W', NULL, 'W', 120, 50, 45, 120, 110, 124, 74, 41, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_122_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_122_W', NULL, 'W', 122, 50.5, 45, 122, 112, 126, 75, 41, 55, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_W', NULL, 'W', 124, 51, 46, 124, 114, 128, 75, 42, 56, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_W_PG', NULL, 'W_PG', 124, 51, 47, 124, 130, 138, 77, 44, 58, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_126_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_126_W', NULL, 'W', 126, 51.5, 46, 126, 116, 130, 76, 44, 58, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_128_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_128_W', NULL, 'W', 128, 52, 47, 128, 118, 132, 76, 45, 59, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_128_W_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_128_W_PG', NULL, 'W_PG', 128, 52, 48, 128, 134, 142, 77, 47, 61, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_130_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_130_W', NULL, 'W', 130, 52.5, 48, 130, 120, 134, 77, 48, 62, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_132_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_132_W', NULL, 'W', 132, 53, 48, 132, 122, 136, 77, 49, 63, 25, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_136_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_136_W', NULL, 'W', 136, 54, 49, 136, 126, 140, 78, 49, 63, 26, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_140_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_140_W', NULL, 'W', 140, 55, 50, 140, 130, 144, 79, 51, 65, 27, NULL, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_90_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_90_WH', NULL, 'WH', 90, 42.5, 37, 90, 82, 88, 69, 32, 46, 54, 21, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_92_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_92_WH', NULL, 'WH', 92, 43, 38, 92, 84, 90, 69, 32, 46, 54, 21, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_94_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_94_WH', NULL, 'WH', 94, 43.5, 38, 94, 86, 92, 70, 33, 47, 54, 22, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_96_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_96_WH', NULL, 'WH', 96, 44, 39, 96, 88, 94, 70, 33, 47, 54, 22, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_98_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_98_WH', NULL, 'WH', 98, 44.5, 39, 98, 90, 96, 71, 34, 48, 54, 23, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_100_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_100_WH', NULL, 'WH', 100, 45, 40, 100, 92, 98, 71, 34, 48, 55, 23, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_102_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_102_WH', NULL, 'WH', 102, 45.5, 40, 102, 94, 100, 72, 35, 49, 55, 24, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_104_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_104_WH', NULL, 'WH', 104, 46, 41, 104, 96, 102, 72, 35, 49, 55, 24, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_106_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_106_WH', NULL, 'WH', 106, 46.5, 41, 106, 98, 104, 73, 36, 50, 55, 25, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_WH', NULL, 'WH', 108, 47, 42, 108, 100, 106, 73, 36, 50, 55, 25, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_108_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_108_WH_PG', NULL, 'WH_PG', 108, 47, 43, 108, 114, 122, 73, 38, 52, 55, 26, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_110_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_110_WH', NULL, 'WH', 110, 47.5, 42, 110, 102, 110, 74, 37, 51, 56, 26, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_WH', NULL, 'WH', 112, 48, 43, 112, 102, 112, 74, 37, 51, 56, 26, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_112_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_112_WH_PG', NULL, 'WH_PG', 112, 48, 44, 112, 118, 126, 74, 39, 53, 55, 27, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_WH', NULL, 'WH', 114, 48.5, 43, 114, 104, 116, 74, 39, 53, 56, 27, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_114_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_114_WH_PG', NULL, 'WH_PG', 114, 48.5, 44, 114, 120, 128, 75, 41, 55, 56, 28, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_WH', NULL, 'WH', 116, 49, 44, 116, 106, 118, 75, 39, 53, 56, 27, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_116_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_116_WH_PG', NULL, 'WH_PG', 116, 49, 45, 116, 122, 130, 77, 41, 55, 56, 28, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_118_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_118_WH', NULL, 'WH', 118, 49.5, 44, 118, 108, 120, 76, 40, 54, 57, 28, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_120_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_120_WH', NULL, 'WH', 120, 50, 45, 120, 110, 124, 76, 41, 55, 57, 28, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_122_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_122_WH', NULL, 'WH', 122, 50.5, 45, 122, 112, 126, 77, 41, 55, 57, 29, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_WH', NULL, 'WH', 124, 51, 46, 124, 114, 128, 77, 42, 56, 57, 29, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_124_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_124_WH_PG', NULL, 'WH_PG', 124, 51, 47, 124, 130, 138, 79, 44, 58, 57, 30, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_126_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_126_WH', NULL, 'WH', 126, 51.5, 46, 126, 116, 130, 78, 44, 58, 58, 31, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_128_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_128_WH', NULL, 'WH', 128, 52, 47, 128, 118, 132, 78, 45, 59, 58, 31, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_128_WH_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_128_WH_PG', NULL, 'WH_PG', 128, 52, 48, 128, 134, 142, 78, 47, 61, 58, 32, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_130_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_130_WH', NULL, 'WH', 130, 52.5, 48, 130, 120, 134, 79, 48, 62, 59, 32, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_132_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_132_WH', NULL, 'WH', 132, 53, 48, 132, 122, 136, 79, 49, 63, 57, 33, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_136_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_136_WH', NULL, 'WH', 136, 54, 49, 136, 126, 140, 80, 49, 63, 59, 34, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_140_WH' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_140_WH', NULL, 'WH', 140, 55, 50, 140, 130, 144, 81, 51, 65, 60, 35, 1, @SeedUserId);

-- ---------- CELANA (59 pola) ----------
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '27_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('27_P', 'P', 27, 68, 88, 63, 56, 44, 36, 98, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '28_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('28_P', 'P', 28, 70, 90, 63, 56, 44, 36, 98, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '29_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('29_P', 'P', 29, 72, 92, 64, 57, 45, 37, 100, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '30_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('30_P', 'P', 30, 74, 94, 64, 57, 45, 37, 100, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '31_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('31_P', 'P', 31, 76, 96, 65, 58, 46, 38, 102, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '32_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('32_P', 'P', 32, 78, 98, 65, 58, 46, 38, 102, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '33_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('33_P', 'P', 33, 80, 100, 66, 59, 47, 39, 104, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '34_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('34_P', 'P', 34, 82, 102, 66, 59, 47, 39, 104, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '35_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('35_P', 'P', 35, 84, 104, 67, 60, 48, 40, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '36_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('36_P', 'P', 36, 86, 106, 67, 60, 48, 40, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '37_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('37_P', 'P', 37, 88, 108, 68, 61, 49, 41, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '38_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('38_P', 'P', 38, 90, 110, 68, 61, 49, 41, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '39_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('39_P', 'P', 39, 92, 112, 69, 62, 50, 42, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '40_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('40_P', 'P', 40, 94, 114, 69, 62, 50, 42, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '41_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('41_P', 'P', 41, 96, 116, 71, 63, 52, 44, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '42_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('42_P', 'P', 42, 98, 118, 71, 63, 52, 44, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '43_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('43_P', 'P', 43, 100, 120, 73, 64, 54, 46, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '44_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('44_P', 'P', 44, 102, 122, 73, 64, 54, 46, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '45_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('45_P', 'P', 45, 104, 124, 75, 66, 56, 48, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '46_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('46_P', 'P', 46, 106, 126, 75, 66, 56, 48, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '47_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('47_P', 'P', 47, 108, 128, 77, 68, 58, 50, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '48_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('48_P', 'P', 48, 110, 130, 77, 68, 58, 50, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '49_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('49_P', 'P', 49, 112, 132, 78, 72, 60, 52, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '50_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('50_P', 'P', 50, 114, 134, 78, 72, 60, 52, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '51_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('51_P', 'P', 51, 116, 136, 78, 72, 60, 52, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '52_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('52_P', 'P', 52, 120, 140, 78, 76, 62, 54, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '53_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('53_P', 'P', 53, 124, 144, 78, 76, 62, 54, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '54_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('54_P', 'P', 54, 126, 146, 78, 80, 64, 56, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '55_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('55_P', 'P', 55, 130, 150, 79, 80, 64, 56, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '56_P' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('56_P', 'P', 56, 134, 154, 79, 84, 66, 58, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '26_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('26_W', 'W', 26, 68, 92, 60, 56, 44, 37, 96, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '27_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('27_W', 'W', 27, 70, 94, 60, 56, 44, 37, 96, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '28_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('28_W', 'W', 28, 72, 96, 60, 56, 44, 37, 96, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '29_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('29_W', 'W', 29, 74, 98, 62, 57, 45, 38, 97, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '30_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('30_W', 'W', 30, 76, 100, 62, 57, 45, 38, 97, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '31_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('31_W', 'W', 31, 78, 102, 64, 58, 46, 39, 98, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '32_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('32_W', 'W', 32, 80, 104, 64, 58, 46, 39, 98, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '33_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('33_W', 'W', 33, 82, 106, 66, 59, 47, 40, 99, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '34_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('34_W', 'W', 34, 84, 108, 66, 59, 47, 40, 99, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '35_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('35_W', 'W', 35, 86, 110, 68, 60, 48, 41, 100, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '36_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('36_W', 'W', 36, 88, 112, 68, 60, 48, 41, 100, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '37_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('37_W', 'W', 37, 90, 114, 70, 61, 49, 42, 101, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '38_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('38_W', 'W', 38, 92, 116, 70, 61, 49, 42, 101, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '39_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('39_W', 'W', 39, 94, 118, 72, 62, 50, 43, 102, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '40_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('40_W', 'W', 40, 96, 120, 72, 62, 50, 43, 102, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '41_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('41_W', 'W', 41, 98, 122, 74, 63, 51, 44, 103, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '42_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('42_W', 'W', 42, 100, 124, 74, 63, 51, 44, 103, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '43_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('43_W', 'W', 43, 102, 126, 76, 64, 52, 45, 104, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '44_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('44_W', 'W', 44, 104, 128, 76, 64, 52, 45, 104, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '45_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('45_W', 'W', 45, 106, 130, 78, 65, 53, 46, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '46_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('46_W', 'W', 46, 108, 132, 78, 65, 53, 46, 105, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '47_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('47_W', 'W', 47, 110, 134, 80, 66, 54, 47, 106, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '48_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('48_W', 'W', 48, 112, 136, 80, 66, 54, 47, 106, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '49_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('49_W', 'W', 49, 114, 138, 82, 67, 55, 48, 107, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '50_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('50_W', 'W', 50, 116, 140, 82, 67, 55, 48, 107, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '51_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('51_W', 'W', 51, 118, 142, 84, 68, 56, 49, 108, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '52_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('52_W', 'W', 52, 120, 144, 84, 68, 56, 49, 108, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '53_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('53_W', 'W', 53, 122, 146, 86, 69, 57, 50, 108, 1, @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.pola_celana WHERE kode = '54_W' AND deleted_at IS NULL)
    INSERT INTO tni.pola_celana (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul, lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki, panjang_celana, is_active, created_by)
    VALUES ('54_W', 'W', 54, 124, 148, 86, 69, 57, 50, 108, 1, @SeedUserId);

-- Verifikasi (subquery tidak boleh langsung di dalam PRINT/CONCAT -- tampung dulu ke variabel).
DECLARE @CntKemeja INT = (SELECT COUNT(*) FROM tni.pola_kemeja WHERE deleted_at IS NULL);
DECLARE @CntCelana INT = (SELECT COUNT(*) FROM tni.pola_celana WHERE deleted_at IS NULL);
PRINT CONCAT('pola_kemeja hidup: ', @CntKemeja, ' (harus 98)');
PRINT CONCAT('pola_celana hidup: ', @CntCelana, ' (harus 59)');
