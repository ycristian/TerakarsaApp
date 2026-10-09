/* =============================================================
   tni.v_stok_pola -- SATU SUMBER ANGKA STOK (Prompt 64)

   TIDAK ADA TABEL SALDO: saldo selalu SUM(qty) dari tni.stok_mutasi.
   Stok bersifat ANONIM per pola -- kemeja LD_102_P mana pun boleh dipakai
   siapa pun yang polanya sama.

   Satu baris per pola (kemeja & celana, TERMASUK yang saldonya 0) per order.
   Semua SP stok, saran Perintah Kerja (Prompt 65), dan dashboard kebutuhan
   size (Prompt 69) membaca view ini.

   Kolom:
     masuk          SUM qty MASUK
     terpakai       SUM qty TERPAKAI dibalik tandanya (positif)
     keluar_lain    SUM qty RUSAK + KOREKSI (apa adanya, bisa negatif/positif)
     bongkar        SUM qty BONGKAR (pengembalian dari pembatalan set)
     saldo          SUM semua qty
     dijatah        personel berstatus DICETAK yang memakai pola ini --
                    kartunya sudah keluar, barangnya dianggap sudah dijatah
     stok_bebas     saldo - dijatah; dipakai saran Perintah Kerja supaya dua
                    perintah kerja tidak menghitung barang yang sama.
                    HANYA INFORMASI -- scan tidak pernah ditolak karenanya.
     kebutuhan_sisa personel BELUM_CETAK + DICETAK yang memakai pola ini

   Urutan tampilan stok (2026-10-07, permintaan owner) -- SEMUA tampilan stok
   urut: urut_gender, urut_varian, urut_size, kode.
     grup_gender    kemeja P | PG | W | WH  (W_PG ikut W, WH_PG ikut WH)
                    celana P | W
     urut_gender    1 P, 2 PG, 3 W, 4 WH
     urut_varian    0 biasa, 1 versi gemuk (W_PG/WH_PG) -- di bawah grupnya
     urut_size      lingkar_dada_acuan (kemeja) / size_angka (celana)
     Rumusnya HANYA di tni.v_pola_urut (di bawah) -- dipakai juga riwayat setoran.
   ============================================================= */

-- Urutan pola untuk semua tampilan stok -- lihat keterangan di atas.
-- Termasuk pola yang sudah dihapus (lookup urutan/kode untuk mutasi lama).
CREATE OR ALTER VIEW tni.v_pola_urut
AS
SELECT 'KEMEJA'                              AS jenis_item,
       pk.pola_kemeja_id                     AS pola_id,
       pk.kode,
       pk.target_gender,
       CAST(CASE WHEN pk.target_gender LIKE 'WH%' THEN 'WH'
                 WHEN pk.target_gender LIKE 'W%'  THEN 'W'
                 ELSE pk.target_gender END AS VARCHAR(10)) AS grup_gender,
       CASE WHEN pk.target_gender = 'P'  THEN 1
            WHEN pk.target_gender = 'PG' THEN 2
            WHEN pk.target_gender LIKE 'WH%' THEN 4
            WHEN pk.target_gender LIKE 'W%'  THEN 3
            ELSE 9 END                       AS urut_gender,
       CASE WHEN pk.target_gender IN ('W_PG','WH_PG') THEN 1 ELSE 0 END AS urut_varian,
       CAST(pk.lingkar_dada_acuan AS DECIMAL(6,1)) AS urut_size
FROM tni.pola_kemeja pk

UNION ALL

SELECT 'CELANA',
       pc.pola_celana_id,
       pc.kode,
       pc.target_gender,
       CAST(pc.target_gender AS VARCHAR(10)),
       CASE pc.target_gender WHEN 'P' THEN 1 WHEN 'W' THEN 3 ELSE 9 END,
       0,
       CAST(pc.size_angka AS DECIMAL(6,1))
FROM tni.pola_celana pc;
GO

CREATE OR ALTER VIEW tni.v_stok_pola
AS
-- ---------------- KEMEJA ----------------
SELECT o.order_id,
       'KEMEJA'                              AS jenis_item,
       pk.pola_kemeja_id                     AS pola_id,
       pk.kode,
       pk.is_active,
       ISNULL(m.masuk, 0)                    AS masuk,
       ISNULL(m.terpakai, 0)                 AS terpakai,
       ISNULL(m.keluar_lain, 0)              AS keluar_lain,
       ISNULL(m.bongkar, 0)                  AS bongkar,
       ISNULL(m.saldo, 0)                    AS saldo,
       ISNULL(v.dijatah, 0)                  AS dijatah,
       ISNULL(m.saldo, 0) - ISNULL(v.dijatah, 0) AS stok_bebas,
       ISNULL(v.kebutuhan_sisa, 0)           AS kebutuhan_sisa,
       u.target_gender,
       u.grup_gender,
       u.urut_gender,
       u.urut_varian,
       u.urut_size
FROM tni.orders o
CROSS JOIN tni.pola_kemeja pk
JOIN tni.v_pola_urut u ON u.jenis_item = 'KEMEJA' AND u.pola_id = pk.pola_kemeja_id
OUTER APPLY (
    SELECT SUM(CASE WHEN sm.jenis_mutasi = 'MASUK'    THEN sm.qty ELSE 0 END)  AS masuk,
           -SUM(CASE WHEN sm.jenis_mutasi = 'TERPAKAI' THEN sm.qty ELSE 0 END) AS terpakai,
           SUM(CASE WHEN sm.jenis_mutasi IN ('RUSAK','KOREKSI') THEN sm.qty ELSE 0 END) AS keluar_lain,
           SUM(CASE WHEN sm.jenis_mutasi = 'BONGKAR'  THEN sm.qty ELSE 0 END)  AS bongkar,
           SUM(sm.qty)                                                         AS saldo
    FROM tni.stok_mutasi sm
    WHERE sm.order_id = o.order_id
      AND sm.pola_kemeja_id = pk.pola_kemeja_id
      AND sm.deleted_at IS NULL
) m
OUTER APPLY (
    SELECT SUM(CASE WHEN p.status_progres = 'DICETAK' THEN 1 ELSE 0 END) AS dijatah,
           SUM(CASE WHEN p.status_progres IN ('BELUM_CETAK','DICETAK') THEN 1 ELSE 0 END) AS kebutuhan_sisa
    FROM tni.v_personel p
    WHERE p.order_id = o.order_id
      AND p.pola_kemeja_id = pk.pola_kemeja_id
) v
WHERE o.deleted_at IS NULL
  AND pk.deleted_at IS NULL

UNION ALL

-- ---------------- CELANA ----------------
SELECT o.order_id,
       'CELANA'                              AS jenis_item,
       pc.pola_celana_id                     AS pola_id,
       pc.kode,
       pc.is_active,
       ISNULL(m.masuk, 0)                    AS masuk,
       ISNULL(m.terpakai, 0)                 AS terpakai,
       ISNULL(m.keluar_lain, 0)              AS keluar_lain,
       ISNULL(m.bongkar, 0)                  AS bongkar,
       ISNULL(m.saldo, 0)                    AS saldo,
       ISNULL(v.dijatah, 0)                  AS dijatah,
       ISNULL(m.saldo, 0) - ISNULL(v.dijatah, 0) AS stok_bebas,
       ISNULL(v.kebutuhan_sisa, 0)           AS kebutuhan_sisa,
       u.target_gender,
       u.grup_gender,
       u.urut_gender,
       u.urut_varian,
       u.urut_size
FROM tni.orders o
CROSS JOIN tni.pola_celana pc
JOIN tni.v_pola_urut u ON u.jenis_item = 'CELANA' AND u.pola_id = pc.pola_celana_id
OUTER APPLY (
    SELECT SUM(CASE WHEN sm.jenis_mutasi = 'MASUK'    THEN sm.qty ELSE 0 END)  AS masuk,
           -SUM(CASE WHEN sm.jenis_mutasi = 'TERPAKAI' THEN sm.qty ELSE 0 END) AS terpakai,
           SUM(CASE WHEN sm.jenis_mutasi IN ('RUSAK','KOREKSI') THEN sm.qty ELSE 0 END) AS keluar_lain,
           SUM(CASE WHEN sm.jenis_mutasi = 'BONGKAR'  THEN sm.qty ELSE 0 END)  AS bongkar,
           SUM(sm.qty)                                                         AS saldo
    FROM tni.stok_mutasi sm
    WHERE sm.order_id = o.order_id
      AND sm.pola_celana_id = pc.pola_celana_id
      AND sm.deleted_at IS NULL
) m
OUTER APPLY (
    SELECT SUM(CASE WHEN p.status_progres = 'DICETAK' THEN 1 ELSE 0 END) AS dijatah,
           SUM(CASE WHEN p.status_progres IN ('BELUM_CETAK','DICETAK') THEN 1 ELSE 0 END) AS kebutuhan_sisa
    FROM tni.v_personel p
    WHERE p.order_id = o.order_id
      AND p.pola_celana_id = pc.pola_celana_id
) v
WHERE o.deleted_at IS NULL
  AND pc.deleted_at IS NULL;
GO
