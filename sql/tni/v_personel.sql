/* =============================================================
   tni.v_personel -- SATU SUMBER STATUS personel (Prompt 60)

   Kolom *_perangkat_id ikut diekspos (perangkat tanpa login, 2026-10-02):
   set_by/boxed_by/printed_by tetap USER id; PERANGKAT yang sebenarnya
   mengerjakan ada di kolom *_perangkat_id (nama petugas = perangkat.nama_petugas, alter_75).

   SEMUA SP baca di seri 60-69 WAJIB memakai view ini untuk status.
   JANGAN menulis ulang logika CASE status_progres di SP lain.

   status_progres diturunkan, bukan disimpan:
     boxed_at terisi + box.shipped_at terisi -> TERKIRIM
     boxed_at terisi                         -> MASUK_BOX
     set_at terisi                           -> SET_JADI
     printed_at terisi                       -> DICETAK
     selain itu                              -> BELUM_CETAK

   Hanya personel hidup (deleted_at IS NULL). Satuan & area di-INNER JOIN
   (keduanya wajib ada); box di-LEFT JOIN dengan filter deleted_at
   DILETAKKAN DI KLAUSA ON -- kalau ditaruh di WHERE, personel yang
   box-nya terhapus akan hilang dari view.

   box_packed_at / box_shipped_at ikut diekspos supaya SP box, scan, dan
   halaman publik tidak perlu menjoin tni.box lagi.
   ============================================================= */

CREATE OR ALTER VIEW tni.v_personel
AS
SELECT
    p.personel_id,
    p.order_id,
    -- wilayah
    s.area_id,
    a.area_code,
    a.area_name,
    a.kota,
    p.satuan_id,
    s.satuan_code,
    s.satuan_name,
    -- identitas
    p.kode_ref,
    p.no_urut,
    p.qr_token,
    p.pangkat,
    p.nama,
    p.nrp,
    p.no_hp,
    p.gender,
    p.tinggi_badan,
    p.berat_badan,
    p.kategori,
    -- pola
    p.pola_kemeja_id,
    pk.kode             AS pola_kemeja_kode,
    pk.kode_alt         AS pola_kemeja_kode_alt,
    pk.target_gender    AS pola_kemeja_gender,
    p.pola_celana_id,
    pc.kode             AS pola_celana_kode,
    pc.target_gender    AS pola_celana_gender,
    p.size_baju_isian,
    p.size_celana_isian,
    p.email_pengisi,
    p.submitted_at,
    -- 8 ukuran badan kemeja
    p.lingkar_leher,
    p.lebar_bahu,
    p.lingkar_dada,
    p.lingkar_perut,
    p.panjang_badan_depan,
    p.panjang_lengan,
    p.lingkar_lengan,
    p.lingkar_ketiak,
    -- 7 ukuran badan celana
    p.lingkar_pinggang_celana,
    p.lingkar_pinggul,
    p.lingkar_pesak,
    p.lingkar_paha,
    p.lingkar_lutut,
    p.lingkar_celana_bawah,
    p.panjang_celana,
    -- review
    p.status_data,
    p.catatan_review,
    -- jejak alur
    p.printed_at,
    p.printed_by,
    p.printed_perangkat_id,
    p.print_count,
    p.set_at,
    p.set_by,
    p.set_perangkat_id,
    p.boxed_at,
    p.boxed_by,
    p.boxed_perangkat_id,
    p.box_id,
    p.urut_dalam_box,
    b.box_code,
    b.packed_at          AS box_packed_at,
    b.shipped_at         AS box_shipped_at,
    b.kapasitas          AS box_kapasitas,
    b.packed_perangkat_id  AS box_packed_perangkat_id,
    b.shipped_perangkat_id AS box_shipped_perangkat_id,
    -- audit
    p.created_at,
    p.created_by,
    p.updated_at,
    p.updated_by,
    -- STATUS TURUNAN
    CASE
        WHEN p.boxed_at IS NOT NULL AND b.shipped_at IS NOT NULL THEN 'TERKIRIM'
        WHEN p.boxed_at IS NOT NULL                              THEN 'MASUK_BOX'
        WHEN p.set_at   IS NOT NULL                              THEN 'SET_JADI'
        WHEN p.printed_at IS NOT NULL                            THEN 'DICETAK'
        ELSE 'BELUM_CETAK'
    END AS status_progres
FROM tni.personel p
JOIN tni.satuan s
  ON s.satuan_id = p.satuan_id
 AND s.deleted_at IS NULL
JOIN tni.area_rawatan a
  ON a.area_id = s.area_id
 AND a.deleted_at IS NULL
JOIN tni.pola_kemeja pk
  ON pk.pola_kemeja_id = p.pola_kemeja_id
JOIN tni.pola_celana pc
  ON pc.pola_celana_id = p.pola_celana_id
LEFT JOIN tni.box b
  ON b.box_id = p.box_id
 AND b.deleted_at IS NULL     -- filter di ON, bukan WHERE
WHERE p.deleted_at IS NULL;
GO
