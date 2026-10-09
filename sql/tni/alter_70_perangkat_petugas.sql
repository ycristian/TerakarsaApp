/* =============================================================
   PDH TNI AD -- perangkat (tanpa login) & petugas per sesi.

   Permintaan owner (2026-10-02): modul /tni dipakai SEPERTI STASIUN --
   masuk cukup dengan KODE PAIRING, tanpa login JWT sama sekali.
   TERPISAH dari tabel `stations`: perangkat TNI tidak terikat divisi
   maupun resource produksi (order PDH tidak punya line produksi).

   Dua tabel baru:
     tni.perangkat  -- 1 baris per tablet/HP; token dirotasi saat pairing
                       & unpair, meniru alur stations (Prompt 20).
     tni.petugas    -- daftar nama petugas; dipilih per SESI di perangkat.

   IDENTITAS AKTOR -- aturan CLAIM.md tetap dipegang:
     created_by / updated_by SELALU user id (di sini: user sistem TNI),
     petugas BUKAN user, jadi disimpan di kolom TERSENDIRI *_petugas_id
     (sejajar dengan resource_id di log produksi, bukan menggantikan
     created_by). Petugas tidak pernah jadi created_by.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- tni.perangkat
-- ============================================================
IF OBJECT_ID('tni.perangkat','U') IS NULL
CREATE TABLE tni.perangkat(
 perangkat_id int primary key identity(1,1),
 perangkat_code varchar(30) not null,
 perangkat_name varchar(150) not null,
 perangkat_token varchar(64) not null,      -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 pairing_code varchar(10) null,             -- kode aktif; NULL = tidak ada
 pairing_code_expires_at datetime2 null,
 paired_at datetime2 null,                  -- kapan perangkat terakhir berhasil klaim
 last_seen_at datetime2 null,
 keterangan varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============================================================
-- tni.petugas -- dipilih per sesi di perangkat; BUKAN user, BUKAN resource
-- ============================================================
IF OBJECT_ID('tni.petugas','U') IS NULL
CREATE TABLE tni.petugas(
 petugas_id int primary key identity(1,1),
 nama varchar(150) not null,
 is_active bit not null default 1,
 keterangan varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============================================================
-- Kolom petugas pada tabel jejak. SEMUA nullable: baris lama (dan aksi
-- dari user yang login) tidak punya petugas, dan pembacaan memakai
-- COALESCE(petugas.nama, Users.FullName).
-- ============================================================
IF COL_LENGTH('tni.personel','printed_petugas_id') IS NULL
    ALTER TABLE tni.personel ADD printed_petugas_id int null
        constraint FK_tni_personel_printed_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.personel','set_petugas_id') IS NULL
    ALTER TABLE tni.personel ADD set_petugas_id int null
        constraint FK_tni_personel_set_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.personel','boxed_petugas_id') IS NULL
    ALTER TABLE tni.personel ADD boxed_petugas_id int null
        constraint FK_tni_personel_boxed_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.box','packed_petugas_id') IS NULL
    ALTER TABLE tni.box ADD packed_petugas_id int null
        constraint FK_tni_box_packed_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.box','shipped_petugas_id') IS NULL
    ALTER TABLE tni.box ADD shipped_petugas_id int null
        constraint FK_tni_box_shipped_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.stok_mutasi','petugas_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD petugas_id int null
        constraint FK_tni_stok_mutasi_petugas foreign key references tni.petugas(petugas_id);
GO
IF COL_LENGTH('tni.pembatalan','petugas_id') IS NULL
    ALTER TABLE tni.pembatalan ADD petugas_id int null
        constraint FK_tni_pembatalan_petugas foreign key references tni.petugas(petugas_id);
GO

-- ============================================================
-- Index
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_code' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE UNIQUE INDEX UX_tni_perangkat_code   ON tni.perangkat(perangkat_code) WHERE deleted_at IS NULL;
GO
-- Token dipakai tiap request: unik TANPA filter deleted_at supaya token
-- perangkat yang dihapus tidak pernah dipakai ulang.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_token' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE UNIQUE INDEX UX_tni_perangkat_token  ON tni.perangkat(perangkat_token);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_perangkat_pairing' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE INDEX IX_tni_perangkat_pairing       ON tni.perangkat(pairing_code) WHERE pairing_code IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_petugas_nama' AND object_id = OBJECT_ID('tni.petugas'))
    CREATE UNIQUE INDEX UX_tni_petugas_nama     ON tni.petugas(nama) WHERE deleted_at IS NULL;
GO

PRINT 'tni.perangkat & tni.petugas siap.';
GO
