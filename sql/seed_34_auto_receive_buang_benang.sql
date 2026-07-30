-- Prompt 34 (lanjutan) -- OPSIONAL: aktifkan auto_receive = 1 untuk semua step
-- "Buang Benang" yang sudah ada, baik di template maupun di workflow artikel yang
-- sudah dibuat. Idempotent -- aman dijalankan berkali-kali (UPDATE ke nilai yang
-- sama tidak merusak apa pun).
--
-- CATATAN PENAMAAN: divisi yang dimaksud "Buang Benang" di prompt asli TERNYATA
-- sudah ada di DB dengan nama "Trim" (division_code = 'Trim', division_id = 9) --
-- lihat sql/migration_33_split_buang_benang.sql yang mengonfirmasi ini lewat query
-- 0.1d. Pola pencarian di bawah karena itu dicari lewat @DivisionNamePattern
-- ('%trim%'), BUKAN '%buang benang%' seperti draft awal permintaan -- kalau nama
-- divisi di DB kamu ternyata beda lagi, cukup ganti isi variabel ini (satu tempat,
-- dipakai di kedua UPDATE di bawah).

DECLARE @DivisionNamePattern VARCHAR(100) = '%trim%';

-- 0. Cek dulu (read-only) divisi mana yang bakal kena, sebelum commit ke UPDATE.
SELECT division_id, division_code, division_name
FROM divisions
WHERE deleted_at IS NULL AND division_name LIKE @DivisionNamePattern;

-- 1. workflow_template_steps: semua baris hidup di divisi yang cocok.
UPDATE wts
SET wts.auto_receive = 1
FROM workflow_template_steps wts
INNER JOIN divisions d ON d.division_id = wts.division_id
WHERE wts.deleted_at IS NULL AND d.deleted_at IS NULL
  AND d.division_name LIKE @DivisionNamePattern;

PRINT 'workflow_template_steps diupdate: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

-- 2. article_workflows: semua baris hidup di divisi yang cocok, lintas semua artikel.
UPDATE aw
SET aw.auto_receive = 1
FROM article_workflows aw
INNER JOIN divisions d ON d.division_id = aw.division_id
WHERE aw.deleted_at IS NULL AND d.deleted_at IS NULL
  AND d.division_name LIKE @DivisionNamePattern;

PRINT 'article_workflows diupdate: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
