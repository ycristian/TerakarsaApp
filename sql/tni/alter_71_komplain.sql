/* =============================================================
   PDH TNI AD -- komplain ukuran dari halaman QR /t/{token} (2026-10-06).

   Permintaan owner: komplain BOLEH dikirim orang luar TANPA perangkat
   terdaftar / login. No telp & komentar WAJIB. Komentar boleh berbaris
   banyak (disimpan apa adanya, termasuk newline).

   created_by tetap user id: user sistem `tni_system` (Tni:SystemUserId),
   karena pengirim bukan user. Bila dikirim dari perangkat terdaftar, petugas
   sesinya ikut dicatat di petugas_id.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tni.komplain','U') IS NULL
CREATE TABLE tni.komplain(
 komplain_id int primary key identity(1,1),
 personel_id int not null foreign key references tni.personel(personel_id),
 no_telp varchar(30) not null,
 komentar nvarchar(2000) not null,
 petugas_id int null foreign key references tni.petugas(petugas_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_komplain_personel' AND object_id = OBJECT_ID('tni.komplain'))
    CREATE INDEX IX_tni_komplain_personel ON tni.komplain(personel_id) WHERE deleted_at IS NULL;
GO

PRINT 'tni.komplain siap.';
GO
