-- Backfill bundles.employee_id dari bundles.resource_person_name (teks bebas lama)
-- ke master employees, dengan mencocokkan (resource_id, nama) ke (employees.resource_id, employee_name).
-- Dibuat manual untuk membantu migrasi data Prompt 32 -- BUKAN bagian dari SP/API.
--
-- Hanya berisi pemetaan yang CUKUP YAKIN (variasi penomoran "1. Nama", typo kecil,
-- spasi/karakter penutup, atau nama gabungan yang hanya punya satu kandidat employee).
-- Yang meragukan/ambigu SENGAJA TIDAK dipetakan -- lihat daftar review di bagian bawah.
--
-- Jalankan manual, review dulu hasil SELECT preview di bagian akhir sebelum lanjut
-- ke prompt drop kolom resource_person_name.

SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#map') IS NOT NULL DROP TABLE #map;
CREATE TABLE #map(
  resource_id int NOT NULL,
  person_name varchar(150) COLLATE DATABASE_DEFAULT NOT NULL,
  employee_id int NOT NULL
);

-- ============ Line A1 (Heru) — resource_id 3 ============
-- employees: Alan(24) Asep(21) Erwin(20) Heru(25) Iki(19) Njah(22) Popot(23)
INSERT INTO #map(resource_id, person_name, employee_id) VALUES
(3,'1. Iki',19),        (3,'Iki',19),
(3,'2. Erwin',20),      (3,'Erwin',20),
(3,'3. Asep',21),       (3,'Asep',21),
(3,'4. Njah',22),       (3,'Njah',22),       (3,'Njahh',22),
(3,'6. Alan',24),       (3,'Alan',24),
(3,'Heru',25),
-- Dikonfirmasi lewat employee_code (SW-XXX = nomor urut asli): SW-005=Popot, SW-001=Iki
(3,'5. Papat',23),      (3,'Papat',23),      (3,'Papad',23),
(3,'Kiki',19);

-- ============ Line A2 (Uus) — resource_id 7 ============
-- employees: Ade(30) Agus(26) Amih/Apih(29) Dasep(28) Ewok(32) Sigit(31) Uus(33) Wiwin(27)
INSERT INTO #map(resource_id, person_name, employee_id) VALUES
(7,'10.  dasep',28),    (7,'10. Dasep',28),  (7,'Dasep',28),
(7,'11. Amih apih',29), (7,'11. Amih/apih',29),
(7,'Amih',29),          (7,'Amih apih',29),  (7,'Amih/apih',29), (7,'Amih\apih',29),
(7,'Apih',29),          (7,'Apih  amih',29), (7,'Apih amih',29), (7,'Apih apih',29),
(7,'13. Sigit',31),     (7,'Sigit',31),
(7,'14. Ewok',32),      (7,'14.ewok',32),    (7,'Ewok',32),      (7,'Ewog',32),
(7,'8. Agus',26),       (7,'8.agus',26),     (7,'Agus',26),
(7,'9. Wiwin',27),      (7,'Wiwin',27),
(7,'Ade',30),
-- SW-047 = IPAN (employee_id 65, dibuat belakangan)
(7,'47. Ipan',65);

-- ============ Line A3 (Abuy) — resource_id 10 ============
-- employees: Abuy(43) Adi(36) Aji(41) Ari(39) Iki(42) Nur(34) Panji(37) Ujang(38) Yana(40) Yogi(35)
INSERT INTO #map(resource_id, person_name, employee_id) VALUES
(10,'16. Nur',34),      (10,'Nur',34),       (10,'Nuur',34),
(10,'17. Yogi',35),     (10,'Yogi',35),
(10,'18. Adi',36),      (10,'Adi',36),
(10,'19. Panji',37),    (10,'Panji',37),
(10,'20.ujang',38),
(10,'22. Yana',40),     (10,'Yana',40),
(10,'23. Aji',41),      (10,'Aji',41),
(10,'24. Iki',42),      (10,'Iki',42),
(10,'Ari',39),
-- SW-048 = IRFAN (employee_id 66); SW-025 = Abuy (43) -- ambiguitas Nur vs Abuy terjawab
(10,'48. Irfan ',66),
(10,'Nur abuy',43),     (10,'Nur/abuy',43),  (10,'Nur\abuy',43);
-- TIDAK dipetakan (lihat review): 'Ebe'

-- ============ Line A4 (Ijal) — resource_id 11 ============
-- employees: Asep(45) Bram(46) Dewi(48) Diki(53) Ida(47) Ijal(54) Imas(51) Kohar(52) Lilis(50) Nia(44) Zaenal(49)
INSERT INTO #map(resource_id, person_name, employee_id) VALUES
(11,'26. Nia',44),      (11,'Nia',44),
(11,'27. Asep',45),     (11,'27.asep',45),   (11,'Asep',45),
(11,'28. Bram',46),     (11,'Bram',46),
(11,'29. Ida',47),      (11,'Ida',47),
(11,'30. Dewi',48),     (11,'30.dewi',48),   (11,'Dewi',48),
(11,'31. Jaenal',49),   (11,'31. Zaenal',49),(11,'Zaenal',49),   (11,'Jenal',49),
(11,'32.lilis',50),     (11,'Lilis',50),
(11,'33. Imas',51),     (11,'Imas',51),
(11,'Kohar',52),
-- SW-028=Bram SW-029=Ida SW-031=Zaenal SW-033=Imas SW-026=Nia -- ambiguitas kombo terjawab
(11,'28',46),           (11,'29',47),        (11,'31',49),       (11,'33',51),
(11,'Ida/imas',47),     (11,'Nia/lilis',44);

-- ============ Line A5 (Risma) — resource_id 12 ============
-- employees: Adiyana(63) Agus(58) Awan(59) Dani(64) Diki(62) Fadil(60) Risma(55) Ujang(61) Wawan(57) Yayat(56)
INSERT INTO #map(resource_id, person_name, employee_id) VALUES
(12,'37. Risma',55),    (12,'Risma ',55),
(12,'39. Wawan ',57),   (12,'Wawan',57),
(12,'40. Agus',58),     (12,'Agus',58),
(12,'42. Fadil',60),    (12,'42. Padil',60), (12,'40. Fadil',60),(12,'Fadil',60),
(12,'43. Ujang',61),    (12,'43.ujang',61),  (12,'Ujang',61),
(12,'44. Diki',62),     (12,'Diki',62),
(12,'45. Ade yana',63), (12,'45. Adeyana',63),(12,'Ade yana',63),(12,'Adeyana',63),
(12,'46. Dani',64),     (12,'Dani',64),
(12,'Awan',59),
(12,'Yayat',56),
-- SW-037=Risma SW-039=Wawan SW-040=Agus SW-042=Fadil SW-046=Dani SW-049=Abdul(67, baru dibuat)
(12,'37',55),           (12,'39',57),        (12,'40',58),       (12,'42',60),      (12,'46',64),
(12,'49. Abdul',67);
-- TIDAK dipetakan (lihat review): 'Rizal'

-- ============ Line B1 (Irwan) — resource_id 13 ============
-- Belum ada satupun employee terdaftar untuk line ini di master -- 'Group irwam' TIDAK
-- bisa dipetakan sampai employee-nya dibuat dulu di CRUD master.

-- ================= PREVIEW sebelum UPDATE =================
-- Cek dulu jumlah baris yang akan kena update per employee.
SELECT m.resource_id, m.person_name, m.employee_id, e.employee_name, COUNT(*) AS bundle_rows
FROM bundles b
JOIN #map m ON m.resource_id = b.resource_id
           AND m.person_name = b.resource_person_name
JOIN employees e ON e.employee_id = m.employee_id
WHERE b.deleted_at IS NULL AND b.employee_id IS NULL
GROUP BY m.resource_id, m.person_name, m.employee_id, e.employee_name
ORDER BY m.resource_id, e.employee_name;

-- ================= UPDATE (jalankan setelah preview di atas dicek) =================
-- Tidak menyentuh updated_at/updated_by -- ini backfill data lama, bukan aksi user.
/*
UPDATE b
SET b.employee_id = m.employee_id
FROM bundles b
JOIN #map m ON m.resource_id = b.resource_id
           AND m.person_name = b.resource_person_name
WHERE b.deleted_at IS NULL AND b.employee_id IS NULL;
*/

-- ================= Sisa yang TIDAK terpetakan (untuk keputusan manual) =================
SELECT b.resource_id, r.resource_name, b.resource_person_name, COUNT(*) AS bundle_rows
FROM bundles b
LEFT JOIN resources r ON r.resource_id = b.resource_id
WHERE b.deleted_at IS NULL AND b.employee_id IS NULL AND b.resource_person_name IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM #map m WHERE m.resource_id = b.resource_id AND m.person_name = b.resource_person_name
  )
GROUP BY b.resource_id, r.resource_name, b.resource_person_name
ORDER BY r.resource_name, b.resource_person_name;

/*
Nomor di depan resource_person_name lama ("1. Iki", "28", "47. Ipan", dst) ternyata
adalah nomor urut employee_code (SW-0XX) -- terkonfirmasi lewat pencocokan employee_code
existing (lihat percakapan). Semua kombo ambigu ("Nur abuy", "Ida/imas", "Nia/lilis")
dan baris angka-doang ("28","29","31","33","37","39","40","42","46") sudah terjawab
lewat kode ini dan masuk ke #map di atas.

Sisa yang MASIH sengaja dikosongkan (bukan asal skip):

Line A3 (10): 'Ebe' (3 baris) -- tidak ada kandidat employee/kode yang cocok.
Line A5 (12): 'Rizal' (1 baris) -- tidak ada kandidat employee/kode yang cocok.

Line B1 (13): 'Group irwam' (2 baris) -- line ini belum punya employee terdaftar
  sama sekali di master.
*/
